require "test_helper"

module Statements
  # Codes come from config/bank_codes.yml (the risk team's notes in tmp/bankcodes)
  class CategorizerTest < ActiveSupport::TestCase
    def categorize(description, amount, **codes)
      Categorizer.call(description: description, counterparty: nil, amount: amount, **codes)
    end

    test "MCC wins, from its own column or from the description" do
      assert_equal "groceries", categorize("POS CARREFOUR MCC:5411", -45)[:category]
      assert_equal "gambling", categorize("payment", -10, mcc: "7995")[:category]
      assert_equal "gambling", categorize("lottery", -5, mcc: "7801")[:category] # 7800-7802 range
      assert_equal "pawn_shop", categorize("x", -100, mcc: "5933")[:category]
    end

    test "MCC 6051 is crypto only when the merchant name says so" do
      assert_equal "crypto", categorize("BINANCE", -500, mcc: "6051")[:category]
      assert_equal "quasi_cash", categorize("SOME SHOP", -500, mcc: "6051")[:category]
    end

    test "ISO 8583 processing code is used when there is no MCC" do
      assert_equal "cash_withdrawal", categorize("x", -100, transaction_code: "010000")[:category]
      assert_equal "refund", categorize("x", 30, transaction_code: "20")[:category]
    end

    test "keywords cover plain statements" do
      assert_equal({ category: "salary", category_group: "income", mcc: nil }, categorize("ხელფასი შპს ალფა", 2500))
      assert_equal "gambling", categorize("CRYSTALBET.GE", -150)[:category]
      assert_equal "loan_repayment", categorize("სესხის დაფარვა კრედო ბანკი", -420)[:category]
      assert_equal "fees_penalties", categorize("ჯარიმა ვადაგადაცილებისთვის", -15)[:category]
      assert_equal "transfer_in", categorize("unknown incoming", 50)[:category]
      assert_equal "other", categorize("unknown outgoing", -50)[:category]
    end

    test "every category in the yml has a valid group" do
      BankCodes.categories.each { |c| assert_includes BankCodes.groups, BankCodes.group_for(c) }
      BankCodes.data["mcc"].each_value { |e| assert_includes BankCodes.categories, e["category"] }
    end
  end
end
