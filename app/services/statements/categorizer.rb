module Statements
  # Stage I of the analysis (see config/bank_codes.yml): one category per operation.
  #
  # Order of evidence:
  #   1. MCC (from its own column, or "MCC:5411" inside the description)
  #   2. ISO 8583 processing code
  #   3. keywords in the description / counterparty (plain statements have no codes)
  # Deterministic on purpose, so the risk indicators don't change between runs.
  module Categorizer
    module_function

    MCC_IN_TEXT = /\bMCC[\s:#-]*(\d{4})\b/i

    CRYPTO_MERCHANTS = /binance|coinbase|kraken|bybit|\bokx\b|kucoin|bitfinex|huobi|crypto|bitcoin|\bbtc\b|\busdt\b|
                        ethereum|კრიპტო|крипто/xi

    LENDERS = %w[
      credo crystal\b rico lazika swiss\s?capital mogo vivus moneyman giro\s?credit finca ფინკა
      alpha\s?express express\s?credit cash\s?point lombard ლომბარდ
    ].join("|")

    # [category, direction (nil = both), pattern]; first match wins
    KEYWORD_RULES = [
      [ "gambling", nil, /crystalbet|adjarabet|europebet|betlive|crocobet|leaderbet|ambassadoribet|1xbet|betsson|
                         pokerstars|ggpoker|stake\.com|bet365|parimatch|vbet|melbet|bwin|unibet|winbet|lotto|
                         casino|კაზინო|ტოტალიზატორ|ლატარია|betting|bookmaker|lottery|poker|казино|ставк/xi ],
      [ "crypto", nil, CRYPTO_MERCHANTS ],
      [ "pawn_shop", nil, /lombard|ლომბარდ|pawn|ломбард/i ],
      [ "overdraft_fee", :out, /overdraft|ოვერდრაფტ|овердрафт/i ],
      [ "fees_penalties", :out, /ჯარიმ|penalt|late\s?fee|ვადაგადაცილ|overdue|штраф|пени|просроч|ინკასო|ყადაღ|арест/i ],
      [ "returned_payment", nil, /insufficient|არასაკმარის|declined|უარყოფილ|недостаточно/i ],
      [ "loan_disbursement", :in, /disburs|სესხის\s?(გაცემა|ჩარიცხვა)|loan\s?(issued|payout)|выдача\s?кредит/i ],
      [ "loan_repayment", :out, /loan|სესხ|კრედიტ(?!ი\s?ბარათ)|repayment|install?ment|განვადებ|ipoteka|mortgage|
                                 იპოთეკ|ипотек|кредит|погашени|займ|microfinance|მიკროსაფინანსო|leasing|ლიზინგ|
                                 #{LENDERS}/xi ],
      [ "salary", :in, /ხელფას|salary|payroll|wage|зарплат|заработн|პრემია|bonus|премия/i ],
      [ "pension_social", :in, /პენსი|pension|пенси|სოციალურ|social|დახმარებ|benefit|allowance|пособ/i ],
      [ "cash_withdrawal", :out, /\batm\b|ბანკომატ|cash\s?(withdrawal|out)|ნაღდი|განაღდებ|снятие|наличн/i ],
      [ "cash_deposit", :in, /\batm\b|cash|ნაღდ|შეტან|наличн|terminal|ტერმინალ|pay\s?box|express\s?pay|oppa/i ],
      [ "tax", :out, /\btax\b|საგადასახადო|გადასახად|rs\.ge|შემოსავლების\s?სამსახურ|ხაზინ|налог/i ],
      [ "insurance", :out, /insurance|დაზღვევ|страхов|ალდაგ|aldagi|ardi|არდი|unison/i ],
      [ "utilities", :out, /telasi|თელასი|energo-?pro|ენერგო|\bgwp\b|tbilisi\s?energy|socar|სოკარ|წყალ|კომუნალ|
                            electricity|коммунал|utilit/xi ],
      [ "telecom", :out, /magti|მაგთი|silknet|სილქნეტ|beeline|cellfie|internet|ინტერნეტ|mobile/i ],
      [ "groceries", :out, /supermarket|სუპერმარკეტ|carrefour|nikora|ნიკორა|spar\b|agrohub|goodwill|ori\s?nabiji|
                              ორი\s?ნაბიჯი|fresco|europroduct|ევროპროდუქტ|libre|smart\b/xi ],
      [ "fuel", :out, /gulf|wissol|ვისოლ|rompetrol|lukoil|socar\s?petrol|connect\b|petrol|ბენზინ|fuel/i ],
      [ "restaurants", :out, /restaurant|რესტორან|cafe|კაფე|bar\b|wolt|glovo|bolt\s?food/i ],
      [ "rent", :out, /\brent\b|ქირა|ქირის|аренд/i ],
      [ "refund", :in, /refund|reversal|chargeback|დაბრუნებ|cashback|ქეშბექ|возврат/i ],
      [ "transfer_in", :in, /transfer|გადარიცხვ|перевод|p2p|ჩარიცხვ|incoming/i ],
      [ "money_transfer", :out, /western\s?union|moneygram|ria\b|intel\s?express|unistream|korona|золотая\s?корона/i ],
      [ "p2p_transfer_out", :out, /transfer|გადარიცხვ|перевод|p2p|card\s?to\s?card|ბარათზე/i ],
      [ "card_purchase", :out, /\bpos\b|purchase|შესყიდვ|გადახდ|payment|покупка|оплата|e-?commerce|online/i ]
    ].freeze

    # Returns { category:, category_group:, mcc: }
    def call(description:, counterparty:, amount:, mcc: nil, transaction_code: nil)
      text = [ description, counterparty ].compact.join(" ")
      mcc = mcc.to_s[/\d{4}/] || text[MCC_IN_TEXT, 1]
      direction = amount.to_d.positive? ? :in : :out

      category = from_mcc(mcc, text, direction) ||
                 BankCodes.processing_code(transaction_code)&.fetch("category") ||
                 from_keywords(text, direction)

      { category: category, category_group: BankCodes.group_for(category), mcc: mcc }
    end

    def from_mcc(mcc, text, direction)
      entry = BankCodes.mcc(mcc)
      return unless entry

      category = entry["category"]
      # MCC 6051 is quasi-cash; only the merchant name can show it is crypto
      return "crypto" if category == "quasi_cash" && text.match?(CRYPTO_MERCHANTS)
      # A card MCC on incoming money is usually a refund from that merchant
      return "refund" if direction == :in && %w[ groceries restaurants fast_food fuel ].include?(category)

      category
    end

    def from_keywords(text, direction)
      rule = KEYWORD_RULES.find { |_, dir, pattern| (dir.nil? || dir == direction) && text.match?(pattern) }
      return rule.first if rule

      direction == :in ? "transfer_in" : "other"
    end
  end
end
