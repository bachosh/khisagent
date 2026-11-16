require "test_helper"

module Analysis
  # Layouts as printed by `pdftotext -layout` (made-up data)
  class PdfLayoutParserTest < ActiveSupport::TestCase
    MULTI_CURRENCY = <<~TEXT
      ანგარიშიდან ამონაწერი
      ანგარიშის მფლობელი:                              ტესტ ტესტიშვილი
      ანგარიშის ნომერი:                       GE00BG0000000000000001

                                                                                   GEL      USD   EUR      GBP
      01/05/2026   საწყისი ნაშთი:                                                   100       0      0       0.00
      31/05/2026   საბოლოო ნაშთი:                                                   1 870.5   5      0       0.00

      თარიღი       დანიშნულება                                                     GEL      USD   EUR      GBP

      02/05/2026    გადახდა - თანხა: GEL30.00; ობიექტი: Socar, Tbilisi, 1,RUSTAVELI;  -30.0
                    MCC:5541; თარიღი: 02/05/2026 21:02; ბარათის No: ****1111;

      05/05/2026   ხელფასი შპს ალფა                                            1 800.5

      07/05/2026   ჩარიცხვა USD                                                             5.0
    TEXT

    DEBIT_CREDIT = <<~TEXT
      Bank statement    Account holder: Test User
      Date          Description                         Debit        Credit       Balance
      01.06.2026    Opening balance                                                500.00
      02.06.2026    ATM cash withdrawal                 200.00                     300.00
      03.06.2026    Salary ALPHA LLC                                 1,500.00     1,800.00
    TEXT

    test "reads a multi-currency statement with wrapped descriptions" do
      result = PdfLayoutParser.new([ MULTI_CURRENCY ]).call
      ops = result[:operations]

      assert_equal 3, ops.size
      assert_equal [ BigDecimal("-30"), BigDecimal("1800.5"), BigDecimal("5") ], ops.map { |op| op[:amount] }
      assert_equal %w[ GEL GEL USD ], ops.map { |op| op[:currency] }
      assert_equal Date.new(2026, 5, 2), ops.first[:booked_on]
      assert_includes ops.first[:description], "MCC:5541"
      refute_match(/-30\.0/, ops.first[:description])
      assert_equal "ტესტ ტესტიშვილი", result[:metadata][:account_holder]
      assert_equal({ "GEL" => BigDecimal("100"), "USD" => 0, "EUR" => 0, "GBP" => 0 }, result[:metadata][:opening])

      check = Reconciler.call(ops, opening: result[:metadata][:opening], closing: result[:metadata][:closing])
      assert_equal "ok", check[:status]
    end

    test "reads debit / credit / balance columns" do
      ops = PdfLayoutParser.new([ DEBIT_CREDIT ]).call[:operations]

      assert_equal [ BigDecimal("-200"), BigDecimal("1500") ], ops.map { |op| op[:amount] }
      assert_equal BigDecimal("1800"), ops.last[:balance]
      assert_equal "ok", Reconciler.call(ops)[:status] # running balance
    end

    TBC = <<~TEXT
       ანგარიშის ნომერი:     GE00TB0000000000000001          01/06/2026 - 30/06/2026
       ანგარიშის მფლობელი:   ტესტ ტესტიშვილი

      საწყისი ნაშთი                1500.00 GEL

      საბოლოო ნაშთი                3900.00 GEL                 ინფორმაცია დაუსრულებელი ტრანზაქციების შესახებ

       თარიღი                          დანიშნულება                     დამატებითი ინფორმაცია       გასული      შემოსული   ბალანსი
                                                                                                          თანხა      თანხა

      01/06/2026 POS - Socar, 30.00 GEL,     ბარათით გადახდა MCC: 5541                              30.00                 1470.00
                 ტრანსპორტი, VISA                             TBCBGE22

      05/06/2026 ხელფასი                  შპს ალფა, GE00TB0000000000000002                                      2500.00   3970.00

                                        1-2

       თარიღი                      დანიშნულება                   დამატებითი ინფორმაცია     გასული    შემოსული   ბალანსი
                                                                                                     თანხა    თანხა

      06/06/2026 POS - Spar, 70.00 GEL,         სავაჭრო ობიექტებში შესრულებული              70.00               3900.00

    TEXT

    test "reads a TBC layout: outgoing/incoming columns, shifted pages, glued amounts, undated balances" do
      result = PdfLayoutParser.new([ TBC ]).call
      ops = result[:operations]

      assert_equal [ BigDecimal("-30"), BigDecimal("2500"), BigDecimal("-70") ], ops.map { |op| op[:amount] }
      assert_equal [ BigDecimal("1470"), BigDecimal("3970"), BigDecimal("3900") ], ops.map { |op| op[:balance] }
      assert_includes ops.first[:description], "MCC: 5541"
      assert_includes ops.first[:description], "ტრანსპორტი" # wrapped line right after the date
      refute_match(/70\.00\z/, ops.last[:description])
      assert_equal({ "GEL" => BigDecimal("1500") }, result[:metadata][:opening])
      assert_equal({ "GEL" => BigDecimal("3900") }, result[:metadata][:closing])
      assert_equal "თიბისი ბანკი", result[:metadata][:bank_name]

      check = Reconciler.call(ops, opening: result[:metadata][:opening], closing: result[:metadata][:closing])
      assert_equal({ status: "ok", difference: 0, checked: "totals" }, check)
    end

    test "returns nil for text without a recognizable table" do
      assert_nil PdfLayoutParser.new([ "Dear customer,\nthank you for banking with us.\n" ]).call
    end
  end

  class ReconcilerTest < ActiveSupport::TestCase
    def op(amount, balance = nil) = { amount: BigDecimal(amount.to_s), balance: balance && BigDecimal(balance.to_s) }

    test "totals: opening + operations = closing" do
      ops = [ op(-30), op(50) ]
      assert_equal "ok", Reconciler.call(ops, opening: { "*" => 10 }, closing: { "*" => 30 })[:status]

      result = Reconciler.call(ops, opening: { "*" => 10 }, closing: { "*" => 45 })
      assert_equal "mismatch", result[:status]
      assert_equal BigDecimal("-15"), result[:difference]
    end

    test "running balance works oldest-first and newest-first" do
      oldest_first = [ op(100, 100), op(-30, 70), op(50, 120) ]
      assert_equal "ok", Reconciler.call(oldest_first)[:status]
      assert_equal "ok", Reconciler.call(oldest_first.reverse)[:status]
      assert_equal "mismatch", Reconciler.call([ op(100, 100), op(-30, 90), op(50, 10) ])[:status]
    end

    test "unknown without balances" do
      assert_equal "unknown", Reconciler.call([ op(5), op(6) ])[:status]
    end
  end

  class LLMExtractorTest < ActiveSupport::TestCase
    # Cuts the reply when asked for more than 4 lines, like a reply that hits num_predict
    class CuttingLLM
      attr_reader :calls

      def initialize = @calls = 0

      def chat(messages:, **)
        @calls += 1
        lines = messages.last[:content].split("\n").grep(/\A\d{2}\.\d{2}\.2026/)
        return { content: "{", done_reason: "length" } if lines.size > 4

        ops = lines.map { |line| { date: "2026-01-#{line[0, 2]}", description: "x", amount: -1 } }
        { content: { metadata: {}, operations: ops }.to_json, done_reason: "stop" }
      end
    end

    test "a cut reply is split and re-read instead of losing rows" do
      lines = (1..10).map { |d| format("%02d.01.2026  payment  -1.00", d) }
      llm = CuttingLLM.new
      result = LLMExtractor.new(llm: llm).from_text_pages([ lines.join("\n") ])

      assert_equal 10, result[:operations].size
      assert_operator llm.calls, :>, 1
    end
  end
end
