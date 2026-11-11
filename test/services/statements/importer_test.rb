require "test_helper"

module Statements
  # The CSV/XLSX path needs no LLM: header keywords map the columns
  class ImporterTest < ActiveSupport::TestCase
    class NoLLM
      def self.chat(**) = raise("LLM must not be called for a standard statement")
    end

    def import(ext)
      user = users(:one)
      path = file_fixture("sample_statement.#{ext}")
      statement = user.statements.create!(conversation: user.conversations.create!, filename: path.basename.to_s,
                                          file_kind: ext, file: { io: path.open, filename: path.basename.to_s })
      Importer.new(statement, llm: NoLLM).call
      statement.reload
    end

    %w[ csv xlsx ].each do |ext|
      test "imports the sample #{ext} statement" do
        statement = import(ext)

        assert_equal 85, statement.operations_count
        assert_equal Date.new(2026, 4, 3), statement.period_start
        assert_equal "GEL", statement.currency
        assert_equal "GE29TB7123456789012345", statement.account_number
        assert_equal "გიორგი მაისურაძე", statement.account_holder
        assert_equal 6, statement.operations.where(category: "salary").count
        assert_equal 8, statement.operations.where(category_group: "gambling").count
        assert_equal BigDecimal("4519.35"), statement.operations.last.balance
      end
    end

    test "metrics follow the planted pattern" do
      metrics = Metrics.new(import("csv")).to_h

      assert_equal 6, metrics.dig("indicators", "income_months")
      assert_operator metrics.dig("trends", "gambling_change_pct"), :>, 100
      assert_equal 1, metrics.dig("trends", "new_financial_counterparties").size
      factors = metrics.dig("indicator_score", "factors").map { |f| f["factor"] }
      assert_includes factors, "gambling_over_10pct_of_income"
      assert_includes factors, "penalties_or_overdraft"
    end
  end
end
