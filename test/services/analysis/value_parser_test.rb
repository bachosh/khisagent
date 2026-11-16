require "test_helper"

module Statements
  class ValueParserTest < ActiveSupport::TestCase
    test "parses Georgian, ISO and Excel dates" do
      assert_equal Date.new(2026, 1, 3), ValueParser.date("03.01.2026")
      assert_equal Date.new(2026, 1, 3), ValueParser.date("2026-01-03 14:22")
      assert_equal Date.new(2026, 1, 25), ValueParser.date("25/01/2026")
      assert_equal Date.new(2026, 1, 3), ValueParser.date(46025)
      assert_nil ValueParser.date("ჯამი")
    end

    test "parses amounts in local formats" do
      assert_equal BigDecimal("1234.56"), ValueParser.amount("1 234,56")
      assert_equal BigDecimal("1234.56"), ValueParser.amount("1,234.56")
      assert_equal BigDecimal("1234.56"), ValueParser.amount("1.234,56")
      assert_equal BigDecimal("-300"), ValueParser.amount("(300.00)")
      assert_equal BigDecimal("-300"), ValueParser.amount("-300.00 GEL")
      assert_equal BigDecimal("1500"), ValueParser.amount("1,500")
      assert_nil ValueParser.amount("")
    end
  end
end
