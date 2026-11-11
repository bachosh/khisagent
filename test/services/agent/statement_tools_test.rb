require "test_helper"

module Agent
  module Tools
    class StatementToolsTest < ActiveSupport::TestCase
      setup do
        user = users(:one)
        path = file_fixture("sample_statement.csv")
        @statement = user.statements.create!(conversation: user.conversations.create!, filename: "s.csv", file_kind: "csv",
                                             file: { io: path.open, filename: "s.csv" })
        Statements::Importer.new(@statement).call
        @report = nil
        @registry = StatementTools.action_registry([ @statement ], mode: :report, report_for: @statement,
                                                   on_report: ->(attrs) { @report = attrs })
      end

      def call(name, **args) = @registry.get_action(name).execute(**args)

      test "evidence keeps only operation ids the model was shown" do
        gambling = call("find_operations", group: "gambling")[:operations].map { |op| op[:id] }
        call("submit_risk_report", risk_score: 60, recommendation: "manual_review", summary: "s",
                                   findings: [ { "severity" => "high", "title" => "t", "description" => "d",
                                                 "evidence" => gambling.first(2) + [ 1, 999 ] } ])

        assert_equal gambling.first(2), @report[:findings].first["evidence"]
        assert_equal "high", @report[:risk_level]
      end

      test "the overview shows key operations with ids" do
        overview = call("statement_overview")
        assert overview[:key_operations]["gambling"].all? { |op| op[:category] == "gambling" }
      end

      test "invalid reports are rejected so the model can fix them" do
        assert_raises(ArgumentError) { call("submit_risk_report", risk_score: 140, recommendation: "approve", summary: "x", findings: []) }
        assert_raises(ArgumentError) { call("submit_risk_report", risk_score: 10, recommendation: "maybe", summary: "x", findings: []) }
      end

      test "the model cannot reach statements outside the registry" do
        assert_raises(ArgumentError) { call("monthly_cashflow", statement_id: @statement.id + 1000) }
      end
    end
  end
end
