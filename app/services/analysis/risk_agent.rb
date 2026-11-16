module Statements
  # The agent that writes the credit risk report for one statement.
  # Method and caveats follow the risk notes behind config/bank_codes.yml.
  class RiskAgent
    MAX_ITERATIONS = 14
    LANGUAGES = { "ka" => "Georgian", "en" => "English" }.freeze

    attr_reader :report_attributes

    def initialize(statement, llm_client: LLM.agent_client(temperature: 0.3), locale: I18n.locale, on_action: nil)
      @statement = statement
      @llm_client = llm_client
      @language = LANGUAGES.fetch(locale.to_s, "English")
      @on_action = on_action
    end

    def run
      registry = Agent::Tools::StatementTools.action_registry(
        [ @statement ], mode: :report, language: @language, report_for: @statement,
        on_report: ->(attrs) { @report_attributes = attrs }
      )
      runner = Agent::Runner.new(
        goals: goals, agent_language: Agent::Languages::FunctionCalling.new, action_registry: registry,
        llm_client: @llm_client, environment: Agent::ProgressEnvironment.new(on_action: @on_action || ->(_) {})
      )
      runner.run("Assess the credit risk of the holder of statement #{@statement.id} (#{@statement.filename}) " \
                 "and submit the report in #{@language}.", max_iterations: MAX_ITERATIONS)
      @report_attributes
    end

    def goals
      [
        Agent::Goal.new(priority: 1, name: "Role", description: <<~TEXT.squish),
          You are a credit risk analyst at a consumer lending company in Georgia. A risk manager uploaded the
          bank account statement of a loan applicant. Your report supports their decision; it does not replace it.
          Facts: #{facts}
        TEXT
        Agent::Goal.new(priority: 2, name: "Method", description: <<~TEXT.squish),
          Stage I is done: every operation has a category and a group (income, essential, discretionary,
          loan_payment, transfer, cash_withdrawal, investment, gambling, unknown) from its MCC, processing code
          or description. Stage II is yours. Call statement_overview, then monthly_cashflow and risk_trends.
          Use find_operations and recurring_payments to check the details: read the descriptions of large,
          'other' and 'transfer_in' operations yourself, because the rules miss things (for example a regular
          monthly transfer from the same company is probably salary; a transfer from the holder's own name is
          not income). Judge these indicators: average monthly income and how stable it is; average spending;
          free cash flow; gambling spend; ATM cash; payments to banks, MFOs and pawn shops (possible debt
          burden) and the debt service ratio; the lowest monthly balance. Look for these warning trends:
          #{BankCodes.warning_trends.join('; ')}.
        TEXT
        Agent::Goal.new(priority: 3, name: "Caution", description: <<~TEXT.squish),
          A single operation is never proof of insolvency. Compare spending and obligations with confirmed
          income. MCC describes the merchant, not what was bought: MCC 6051 alone does not prove crypto.
          The indicator_score from statement_overview is a rule-based starting point: keep it unless the
          operations show it is wrong, and explain any big change. Never invent operations, ids or amounts:
          cite as evidence only ids of operations that appear in tool results and that show the finding
          (for gambling, the gambling operations; for loans, the loan payments).
        TEXT
        Agent::Goal.new(priority: 4, name: "Report", description: <<~TEXT.squish)
          Finish by calling #{Agent::Tools::StatementTools::REPORT_TOOL} exactly once. risk_score 0-29 low,
          30-54 medium, 55-79 high, 80+ critical. recommendation: approve, approve_with_conditions,
          manual_review or decline. Give 2 to 8 findings ordered by severity, each with amounts and 1 to 5
          operation ids as evidence, plus strengths. Write summary, titles, descriptions and strengths in
          #{@language}; keep merchant names and amounts as in the statement (currency #{@statement.display_currency}).
          Use only #{@language} words: never mix in words from other languages.
        TEXT
      ]
    end

    private

    def facts
      {
        "file" => @statement.filename,
        "bank" => @statement.bank_name,
        "account holder" => @statement.account_holder,
        "period" => [ @statement.period_start, @statement.period_end ].compact.join(" to "),
        "operations" => @statement.operations_count,
        "currency" => @statement.display_currency,
        "MCC codes present" => @statement.operations.where.not(mcc: nil).exists? ? "yes" : "no (categories come from descriptions)"
      }.compact_blank.map { |k, v| "#{k}: #{v}" }.join("; ")
    end
  end
end
