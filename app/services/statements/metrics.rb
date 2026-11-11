module Statements
  # Stage II of the analysis (config/bank_codes.yml → indicators, warning_trends): financial risk
  # indicators computed from the categorized operations. Pure Ruby, deterministic; the agent reads
  # these through its tools and explains them, the UI shows them on the report page.
  class Metrics
    TRANSFER_OUT = %w[ p2p_transfer_out money_transfer account_funding ].freeze
    DEPLETION_SHARE = 0.1 # "almost nothing left": balance below 10% of the salary
    TREND_MONTHS = 3

    def initialize(statement, operations = nil)
      @statement = statement
      @operations = (operations || statement.operations.to_a).sort_by { |op| [ op.booked_on || Date.new(1900), op.position ] }
    end

    def to_h
      @to_h ||= {
        "overview" => overview,
        "indicators" => indicators,
        "groups" => totals_by(:category_group),
        "categories" => totals_by(:category),
        "monthly" => monthly,
        "trends" => trends,
        "income_sources" => income_sources,
        "financial_counterparties" => financial_counterparties,
        "large_incoming" => large_incoming,
        "indicator_score" => indicator_score
      }
    end

    def overview
      @overview ||= begin
        balances = @operations.filter_map(&:balance)
        {
          "period_start" => first_date&.iso8601,
          "period_end" => last_date&.iso8601,
          "months_covered" => months.size,
          "operations_count" => @operations.size,
          "currency" => @statement.display_currency,
          "total_in" => money(@operations.select(&:incoming?).sum(&:amount)),
          "total_out" => money(-@operations.reject(&:incoming?).sum(&:amount)),
          "opening_balance" => money(@statement.opening_balance || opening_from_first_operation),
          "closing_balance" => money(@statement.closing_balance || balances.last),
          "lowest_balance" => money(balances.min),
          "operations_with_negative_balance" => balances.count(&:negative?),
          "has_balances" => balances.any?,
          "has_mcc" => @operations.any?(&:mcc)
        }
      end
    end

    # The eight indicators listed in the risk notes, as monthly averages over the statement period
    def indicators
      @indicators ||= begin
        income = monthly_series { |ops| ops.select { |op| op.category_group == "income" }.sum(&:amount) }
        expense = monthly_series { |ops| -ops.select { |op| expense?(op) }.sum(&:amount) }
        financial = monthly_series { |ops| -outgoing_in(ops, group: "loan_payment").sum(&:amount) }
        avg_income = average(income)
        avg_financial = average(financial)

        {
          "avg_monthly_income" => money(avg_income),
          "income_variation_pct" => variation_pct(income),
          "income_months" => income.count(&:positive?),
          "avg_monthly_expense" => money(average(expense)),
          "avg_free_cash_flow" => money(avg_income - average(expense)),
          "gambling_per_month" => money(average(monthly_series { |ops| -outgoing_in(ops, group: "gambling").sum(&:amount) })),
          "cash_withdrawals_per_month" => money(average(monthly_series { |ops| -outgoing_in(ops, group: "cash_withdrawal").sum(&:amount) })),
          "cash_withdrawal_count_per_month" => average(monthly_series { |ops| outgoing_in(ops, group: "cash_withdrawal").size }).to_f.round(1),
          "financial_payments_per_month" => money(avg_financial),
          "debt_service_ratio_pct" => avg_income.positive? ? (avg_financial / avg_income * 100).to_f.round(1) : nil,
          "min_monthly_balance" => money(monthly.filter_map { |m| m["min_balance"] }.min),
          "risky_operations" => @operations.count(&:risky?)
        }
      end
    end

    def monthly
      @monthly ||= months.map do |month|
        ops = by_month.fetch(month, [])
        balances = ops.filter_map(&:balance)
        {
          "month" => month,
          "incoming" => money(ops.select(&:incoming?).sum(&:amount)),
          "income" => money(ops.select { |op| op.category_group == "income" }.sum(&:amount)),
          "outgoing" => money(-ops.reject(&:incoming?).sum(&:amount)),
          "expense" => money(-ops.select { |op| expense?(op) }.sum(&:amount)),
          "loan_payments" => money(-outgoing_in(ops, group: "loan_payment").sum(&:amount)),
          "gambling" => money(-outgoing_in(ops, group: "gambling").sum(&:amount)),
          "cash_withdrawals" => money(-outgoing_in(ops, group: "cash_withdrawal").sum(&:amount)),
          "cash_withdrawal_count" => outgoing_in(ops, group: "cash_withdrawal").size,
          "min_balance" => money(balances.min),
          "end_balance" => money(balances.last)
        }
      end
    end

    # The four changes over time from the notes (section 3A): earlier months vs the last TREND_MONTHS
    def trends
      @trends ||= begin
        recent, earlier = monthly.last(TREND_MONTHS), monthly[0...-TREND_MONTHS].to_a
        {
          "compared" => earlier.any? ? "#{earlier.first['month']}..#{earlier.last['month']} vs #{recent.first['month']}..#{recent.last['month']}" : nil,
          "gambling_change_pct" => change_pct(earlier, recent, "gambling"),
          "cash_withdrawal_count_change_pct" => change_pct(earlier, recent, "cash_withdrawal_count"),
          "loan_payments_change_pct" => change_pct(earlier, recent, "loan_payments"),
          "new_financial_counterparties" => new_financial_counterparties,
          "salary_depletion" => salary_depletion
        }
      end
    end

    def income_sources
      @operations.select { |op| op.category_group == "income" }
                 .group_by { |op| counterparty_key(op) }
                 .map { |name, ops| { "name" => name, "count" => ops.size, "total" => money(ops.sum(&:amount)),
                                      "months" => ops.map { |op| month_of(op) }.uniq.size } }
                 .sort_by { |s| -s["total"] }.first(10)
    end

    # Lenders, MFOs, pawn shops: the possible debt burden
    def financial_counterparties
      @financial_counterparties ||= begin
        @operations.select { |op| op.category_group == "loan_payment" && !op.incoming? }
                   .group_by { |op| counterparty_key(op) }
                   .map do |name, ops|
                     active = ops.map { |op| month_of(op) }.uniq.sort
                     { "name" => name, "payments" => ops.size, "total" => money(-ops.sum(&:amount)),
                       "first_month" => active.first, "last_month" => active.last, "months" => active.size }
                   end
                   .sort_by { |c| -c["total"] }
      end
    end

    # One-off incoming amounts that are not income and are large next to it (loans, sales, own transfers?)
    def large_incoming
      avg_income = indicators["avg_monthly_income"].to_f
      threshold = avg_income.positive? ? avg_income * 1.5 : nil
      return [] unless threshold

      @operations.select { |op| op.incoming? && op.category_group != "income" && op.amount.to_f >= threshold }
                 .sort_by { |op| -op.amount }.first(10).map(&:to_tool_hash)
    end

    # A transparent starting point for the agent, not the final score: each factor adds points.
    # The notes warn against scoring directly from MCC codes, so every factor is an indicator.
    def indicator_score
      @indicator_score ||= begin
        ind = indicators
        factors = []
        income = ind["avg_monthly_income"].to_f
        add = ->(points, key) { factors << { "factor" => key, "points" => points } }

        add.(25, "no_identified_income") if income.zero?
        add.(10, "irregular_income") if income.positive? && ind["income_variation_pct"].to_f > 35
        add.(15, "negative_free_cash_flow") if income.positive? && ind["avg_free_cash_flow"].to_f.negative?

        dsr = ind["debt_service_ratio_pct"].to_f
        add.(25, "debt_service_over_50pct") if dsr > 50
        add.(12, "debt_service_over_30pct") if dsr > 30 && dsr <= 50

        gambling_share = income.positive? ? ind["gambling_per_month"].to_f / income * 100 : (ind["gambling_per_month"].to_f.positive? ? 100 : 0)
        add.(25, "gambling_over_10pct_of_income") if gambling_share > 10
        add.(12, "gambling_present") if gambling_share.positive? && gambling_share <= 10

        cash_share = income.positive? ? ind["cash_withdrawals_per_month"].to_f / income * 100 : 0
        add.(8, "cash_withdrawals_over_50pct_of_income") if cash_share > 50
        add.(10, "negative_balance") if overview["operations_with_negative_balance"].positive?
        add.(8, "penalties_or_overdraft") if @operations.any? { |op| %w[ fees_penalties overdraft_fee returned_payment ].include?(op.category) }
        add.(6, "pawn_shop") if @operations.any? { |op| op.category == "pawn_shop" }
        add.(8, "several_new_lenders") if trends["new_financial_counterparties"].size >= 2
        add.(6, "gambling_growing") if trends["gambling_change_pct"].to_f > 50
        add.(4, "cash_withdrawals_more_frequent") if trends["cash_withdrawal_count_change_pct"].to_f > 50
        add.(6, "salary_spent_within_days") if trends.dig("salary_depletion", "avg_days").to_f.between?(0.01, 5)

        { "score" => factors.sum { |f| f["points"] }.clamp(0, 100), "factors" => factors }
      end
    end

    private

    def first_date = @operations.filter_map(&:booked_on).min
    def last_date = @operations.filter_map(&:booked_on).max

    def month_of(op) = op.booked_on&.strftime("%Y-%m") || "unknown"

    def by_month
      @by_month ||= @operations.group_by { |op| month_of(op) }
    end

    def months
      return [] unless first_date

      list = []
      date = first_date.beginning_of_month
      while date <= last_date
        list << date.strftime("%Y-%m")
        date = date.next_month
      end
      list
    end

    def monthly_series(&block)
      months.map { |month| block.call(by_month.fetch(month, [])) }
    end

    def outgoing_in(ops, group:)
      ops.select { |op| op.category_group == group && !op.incoming? }
    end

    # Spending: everything that leaves the account except transfers to other accounts / people
    def expense?(op)
      !op.incoming? && !TRANSFER_OUT.include?(op.category)
    end

    def average(series)
      series.empty? ? 0 : series.sum.to_d / series.size
    end

    # Coefficient of variation of monthly income, in %
    def variation_pct(series)
      mean = average(series)
      return nil unless mean.positive? && series.size > 1

      variance = series.sum { |v| (v.to_d - mean)**2 } / series.size
      (Math.sqrt(variance.to_f) / mean.to_f * 100).round(1)
    end

    def change_pct(earlier, recent, key)
      return nil if earlier.empty? || recent.empty?

      before = earlier.sum { |m| m[key].to_f } / earlier.size
      after = recent.sum { |m| m[key].to_f } / recent.size
      return nil if before.zero? && after.zero?
      return 100.0 if before.zero?

      ((after - before) / before * 100).round(1)
    end

    # Financial counterparties whose first payment is in the last TREND_MONTHS and that were paid more than once
    def new_financial_counterparties
      recent = months.last(TREND_MONTHS)
      return [] if months.size <= TREND_MONTHS

      financial_counterparties.select { |c| recent.include?(c["first_month"]) && c["payments"] > 1 }.map { |c| c["name"] }
    end

    # How many days after each salary the balance falls under 10% of that salary
    def salary_depletion
      salaries = @operations.select { |op| op.category == "salary" && op.balance }
      return { "measured" => 0 } if salaries.empty?

      days = salaries.filter_map do |salary|
        later = @operations.select { |op| op.booked_on && salary.booked_on && op.booked_on >= salary.booked_on && op.position > salary.position && op.balance }
        low = later.find { |op| op.balance < salary.amount * DEPLETION_SHARE }
        (low.booked_on - salary.booked_on).to_i if low
      end
      {
        "measured" => salaries.size,
        "depleted" => days.size,
        "avg_days" => days.any? ? (days.sum.to_f / days.size).round(1) : nil
      }
    end

    def totals_by(attribute)
      @operations.group_by(&attribute).transform_values do |ops|
        { "count" => ops.size, "in" => money(ops.select(&:incoming?).sum(&:amount)),
          "out" => money(-ops.reject(&:incoming?).sum(&:amount)) }
      end.sort_by { |_, v| -(v["in"] + v["out"]) }.to_h
    end

    def opening_from_first_operation
      first = @operations.find(&:balance)
      first && (first.balance - first.amount)
    end

    def counterparty_key(op)
      name = op.counterparty.presence || op.description
      name.to_s.gsub(/\d{4,}|\d+[.,]\d+|\b\d{1,2}[.\/]\d{1,2}[.\/]\d{2,4}\b/, "").squish.truncate(50).presence || "?"
    end

    def money(value)
      value.nil? ? nil : value.to_d.round(2).to_f
    end
  end
end
