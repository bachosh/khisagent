module Analysis
  # Checks that the imported operations are complete and correctly read:
  #   1. opening balance + sum of operations = closing balance (per currency), when the statement prints them;
  #   2. otherwise each operation's balance = previous balance + amount, when there is a balance column.
  # Returns { status: "ok" | "mismatch" | "unknown", difference:, checked: "totals" | "running_balance" | nil }.
  class Reconciler
    TOLERANCE = BigDecimal("0.01")
    RUNNING_OK_SHARE = 0.98

    def self.call(operations, opening: nil, closing: nil)
      new(operations, opening, closing).call
    end

    def initialize(operations, opening, closing)
      @operations = operations
      @opening = opening.to_h
      @closing = closing.to_h
    end

    def call
      by_totals || by_running_balance || { status: "unknown", difference: nil, checked: nil }
    end

    private

    def by_totals
      currencies = @closing.keys & @opening.keys
      return if currencies.empty?

      single = currencies.size == 1
      differences = currencies.map do |currency|
        ops = single ? @operations : @operations.select { |op| (op[:currency] || currency) == currency }
        BigDecimal(@opening[currency].to_s) + ops.sum { |op| op[:amount] } - BigDecimal(@closing[currency].to_s)
      end
      worst = differences.max_by(&:abs)
      { status: worst.abs <= TOLERANCE ? "ok" : "mismatch", difference: worst.round(2), checked: "totals" }
    end

    def by_running_balance
      with_balance = @operations.select { |op| op[:balance] }
      return if with_balance.size < 2 || with_balance.size < @operations.size * 0.9

      pairs = with_balance.each_cons(2).to_a
      oldest_first = pairs.count { |prev, op| (prev[:balance] + op[:amount] - op[:balance]).abs <= TOLERANCE }
      newest_first = pairs.count { |prev, op| (op[:balance] + prev[:amount] - prev[:balance]).abs <= TOLERANCE }
      share = [ oldest_first, newest_first ].max.to_f / pairs.size
      { status: share >= RUNNING_OK_SHARE ? "ok" : "mismatch", difference: nil, checked: "running_balance",
        consistent_share: share.round(3) }
    end
  end
end
