module Agent
  module Tools
    # Tools over parsed bank statements, for the risk report agent and the chat agent.
    #
    # Like khisfari's AccessLogTools these are not in the global ToolRegistry: every run gets its own
    # ActionRegistry bound to the statements it may see (the user's statements in one conversation),
    # so the model can never reach another user's data.
    #
    #   Agent::Tools::StatementTools.action_registry(statements, mode: :report, report_for: statement)
    #   Agent::Tools::StatementTools.action_registry(statements, mode: :chat)
    class StatementTools
      MAX_OPERATIONS = 80
      REPORT_TOOL = "submit_risk_report"

      def self.action_registry(statements, mode:, language: "English", report_for: nil, on_report: nil)
        registry = ActionRegistry.new
        new(statements, mode: mode, language: language, report_for: report_for, on_report: on_report)
          .actions.each { |action| registry.register(action) }
        registry
      end

      def initialize(statements, mode:, language:, report_for:, on_report:)
        @statements = statements.index_by(&:id)
        @mode = mode
        @language = language
        @report_for = report_for
        @on_report = on_report
        @metrics = {}
        @seen_ids = Set.new # operation ids the model has been shown; only these may be cited as evidence
      end

      def actions
        list = [ statement_overview, monthly_cashflow, risk_trends, find_operations, recurring_payments ]
        list << (@mode == :report ? submit_risk_report : final_answer)
        list
      end

      private

      def statement_param
        ids = @statements.keys
        { type: "integer", description: "Statement id (#{ids.join(', ')}). Optional when there is only one." }
      end

      def find_statement(statement_id)
        return @statements.values.first if statement_id.blank? && @statements.size == 1
        return @report_for if statement_id.blank? && @report_for

        @statements[statement_id.to_i] or
          raise ArgumentError, "Unknown statement_id #{statement_id.inspect}. Available: #{@statements.keys.join(', ')}"
      end

      # Records which operations the model has seen, so evidence can be checked
      def shown(rows)
        rows.each { |row| @seen_ids << row[:id] if row[:id] }
        rows
      end

      KEY_GROUPS = %w[ gambling loan_payment cash_withdrawal investment income ].freeze

      # The largest operations of each risk-relevant group, with their ids
      def key_operations(statement)
        result = KEY_GROUPS.to_h do |group|
          [ group, shown(statement.operations.where(category_group: group).reorder(Arel.sql("ABS(amount) DESC")).limit(8).map(&:to_tool_hash)) ]
        end
        risky = Statements::BankCodes.categories.select { |c| Statements::BankCodes.risky?(c) }
        result["risky_categories"] = shown(statement.operations.where(category: risky).where.not(category_group: KEY_GROUPS).limit(10).map(&:to_tool_hash))
        result["loan_disbursements"] = shown(statement.operations.where(category: "loan_disbursement").limit(5).map(&:to_tool_hash))
        result.compact_blank
      end

      def metrics_for(statement)
        @metrics[statement.id] ||= Statements::Metrics.new(statement)
      end

      def statement_overview
        Action.new(
          name: "statement_overview",
          function: lambda do |statement_id: nil|
            statement = find_statement(statement_id)
            m = metrics_for(statement)
            {
              statement: { id: statement.id, file: statement.filename, bank: statement.bank_name,
                           account_holder: statement.account_holder, account: statement.account_number },
              overview: m.overview,
              indicators: m.indicators,
              groups: m.to_h["groups"],
              categories: m.to_h["categories"],
              indicator_score: m.indicator_score,
              key_operations: key_operations(statement)
            }
          end,
          description: "Start here. Period, totals, the risk indicators (average monthly income and its variation, " \
                      "expenses, free cash flow, gambling, ATM cash, payments to financial organisations, debt " \
                      "service ratio, lowest monthly balance), totals per group and category, a rule-based " \
                      "indicator score with the factors behind it, and the key operations of each risk group with their ids.",
          parameters: { type: "object", properties: { statement_id: statement_param }, required: [] }
        )
      end

      def monthly_cashflow
        Action.new(
          name: "monthly_cashflow",
          function: ->(statement_id: nil) { metrics_for(find_statement(statement_id)).monthly },
          description: "Month by month: incoming, income, outgoing, spending, loan payments, gambling, " \
                      "ATM cash (amount and count), lowest and closing balance.",
          parameters: { type: "object", properties: { statement_id: statement_param }, required: [] }
        )
      end

      def risk_trends
        Action.new(
          name: "risk_trends",
          function: lambda do |statement_id: nil|
            m = metrics_for(find_statement(statement_id))
            { trends: m.trends, income_sources: m.income_sources,
              financial_counterparties: m.financial_counterparties,
              large_incoming_not_income: m.large_incoming.each { |op| @seen_ids << op[:id] } }
          end,
          description: "Changes over time (last 3 months vs earlier: gambling, ATM frequency, loan payments, new " \
                      "lenders, how fast the salary is spent), income sources, lenders/MFOs/pawn shops paid, " \
                      "and large incoming amounts that are not income.",
          parameters: { type: "object", properties: { statement_id: statement_param }, required: [] }
        )
      end

      def find_operations
        Action.new(
          name: "find_operations",
          function: lambda do |statement_id: nil, category: nil, group: nil, direction: nil, query: nil,
                               min_amount: nil, date_from: nil, date_to: nil, sort: "date", limit: 40|
            scope = find_statement(statement_id).operations
            scope = scope.where(category: category) if category.present?
            scope = scope.where(category_group: group) if group.present?
            scope = scope.incoming if direction == "in"
            scope = scope.outgoing if direction == "out"
            scope = scope.where("ABS(amount) >= ?", min_amount.to_f) if min_amount.present?
            scope = scope.where("booked_on >= ?", date_from) if date_from.present?
            scope = scope.where("booked_on <= ?", date_to) if date_to.present?
            if query.present?
              like = "%#{Operation.sanitize_sql_like(query.to_s.downcase)}%"
              scope = scope.where("LOWER(description) LIKE :q OR LOWER(counterparty) LIKE :q OR mcc = :code", q: like, code: query.to_s)
            end
            scope = sort == "amount" ? scope.reorder(Arel.sql("ABS(amount) DESC")) : scope.reorder(:booked_on, :position)

            total = scope.count
            rows = shown(scope.limit(limit.to_i.clamp(1, MAX_OPERATIONS)).map(&:to_tool_hash))
            { matched: total, shown: rows.size, sum: scope.sum(:amount).to_f, operations: rows }
          end,
          description: "Search the operations. Filters combine. Returns at most #{MAX_OPERATIONS} rows plus the " \
                      "number and sum of all matches. Operation ids are the row numbers in the statement.",
          parameters: {
            type: "object",
            properties: {
              statement_id: statement_param,
              category: { type: "string", enum: Statements::BankCodes.categories },
              group: { type: "string", enum: Statements::BankCodes.groups },
              direction: { type: "string", enum: %w[ in out ] },
              query: { type: "string", description: "Text in the description or counterparty, or a 4-digit MCC" },
              min_amount: { type: "number", description: "Minimum absolute amount" },
              date_from: { type: "string", description: "YYYY-MM-DD" },
              date_to: { type: "string", description: "YYYY-MM-DD" },
              sort: { type: "string", enum: %w[ date amount ], description: "amount = largest first" },
              limit: { type: "integer", description: "Default 40, max #{MAX_OPERATIONS}" }
            },
            required: []
          }
        )
      end

      def recurring_payments
        Action.new(
          name: "recurring_payments",
          function: lambda do |statement_id: nil|
            ops = find_statement(statement_id).operations.outgoing.to_a
            ops.group_by { |op| (op.counterparty.presence || op.description).to_s.gsub(/[\d.,\/:-]+/, " ").squish.downcase.truncate(40) }
               .filter_map do |name, list|
                 months = list.filter_map { |op| op.booked_on&.strftime("%Y-%m") }.uniq
                 next if months.size < 3 || name.blank?

                 { name: name, months: months.size, payments: list.size, avg_amount: (-list.sum(&:amount) / list.size).round(2).to_f,
                   category: list.map(&:category).tally.max_by(&:last).first }
               end
               .sort_by { |r| -r[:avg_amount] }.first(30)
          end,
          description: "Outgoing payments to the same payee in 3 or more different months (loans, rent, utilities, " \
                      "subscriptions, transfers to the same person), with the average amount.",
          parameters: { type: "object", properties: { statement_id: statement_param }, required: [] }
        )
      end

      def final_answer
        Action.new(
          name: "terminate",
          function: ->(message:) { message },
          description: "Send your final answer to the risk manager. Call it once you have the facts. " \
                      "Write in #{@language}, in Markdown (short paragraphs, bullet lists or small tables).",
          parameters: {
            type: "object",
            properties: { message: { type: "string", description: "The answer, in #{@language}, Markdown" } },
            required: [ "message" ]
          },
          terminal: true
        )
      end

      def submit_risk_report
        Action.new(
          name: REPORT_TOOL,
          function: lambda do |risk_score:, recommendation:, summary:, findings: [], strengths: [],
                               estimated_monthly_income: nil, estimated_monthly_debt_payments: nil|
            report = build_report(risk_score, recommendation, summary, findings, strengths,
                                  estimated_monthly_income, estimated_monthly_debt_payments)
            @on_report&.call(report)
            "Report saved."
          end,
          description: "Submit the final credit risk report. Call exactly once, at the end.",
          parameters: {
            type: "object",
            properties: {
              risk_score: { type: "integer", description: "0 (no risk) to 100 (certain default)" },
              recommendation: { type: "string", enum: RiskReport::RECOMMENDATIONS },
              summary: { type: "string", description: "3 to 6 sentences in #{@language} for the risk manager" },
              findings: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    severity: { type: "string", enum: RiskReport::SEVERITIES },
                    title: { type: "string", description: "Short title in #{@language}" },
                    description: { type: "string", description: "What was found and why it matters, with amounts, in #{@language}" },
                    evidence: { type: "array", items: { type: "integer" },
                                description: "1 to 5 ids of operations you saw in tool results that show this finding" }
                  },
                  required: %w[ severity title description ]
                }
              },
              strengths: { type: "array", items: { type: "string" }, description: "Positive factors, in #{@language}" },
              estimated_monthly_income: { type: "number" },
              estimated_monthly_debt_payments: { type: "number" }
            },
            required: %w[ risk_score recommendation summary findings ]
          },
          terminal: true
        )
      end

      def build_report(score, recommendation, summary, findings, strengths, income, debt)
        score = Integer(score, exception: false) || raise(ArgumentError, "risk_score must be an integer 0-100")
        raise ArgumentError, "risk_score must be between 0 and 100" unless score.between?(0, 100)
        raise ArgumentError, "recommendation must be one of #{RiskReport::RECOMMENDATIONS.join(', ')}" unless RiskReport::RECOMMENDATIONS.include?(recommendation)
        raise ArgumentError, "summary is empty" if summary.blank?

        findings = Array(findings).map do |f|
          f = f.to_h.stringify_keys
          raise ArgumentError, "each finding needs title and description" if f["title"].blank? || f["description"].blank?

          { "severity" => RiskReport::SEVERITIES.include?(f["severity"]) ? f["severity"] : "medium",
            "title" => f["title"].to_s.squish, "description" => f["description"].to_s.strip,
            "evidence" => Array(f["evidence"]).filter_map { |id| Integer(id, exception: false) }.select { |id| @seen_ids.include?(id) }.first(5) }
        end

        { risk_score: score, risk_level: RiskReport.level_for(score), recommendation: recommendation,
          summary: summary.strip, findings: findings, strengths: Array(strengths).map(&:to_s).compact_blank,
          estimated_monthly_income: income, estimated_monthly_debt_payments: debt }
      end
    end
  end
end
