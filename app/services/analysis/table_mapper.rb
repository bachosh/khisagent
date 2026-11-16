module Statements
  # Finds the header row and the meaning of each column in a statement table, then turns the rows
  # into operation hashes. Header keywords cover Georgian, English and Russian bank exports;
  # when they don't match, the LLM is asked to map the columns from a sample.
  class TableMapper
    HEADER_SCAN_ROWS = 40
    FIELDS = %w[ date description counterparty debit credit amount balance currency direction mcc transaction_code ].freeze

    KEYWORDS = {
      "date" => [ "თარიღი", "date", "дата", "posting", "booking", "value date", "transaction date", "datum" ],
      "description" => [ "დანიშნულება", "აღწერა", "შინაარსი", "description", "details", "narrative", "purpose",
                         "назначение", "описание", "детали", "particulars", "memo", "reference", "კომენტარი" ],
      "counterparty" => [ "მიმღები", "გამგზავნი", "კონტრაგენტ", "პარტნიორ", "beneficiary", "counterparty", "payee",
                          "payer", "partner", "merchant", "контрагент", "получатель", "отправитель", "recipient", "sender" ],
      "debit" => [ "დებეტი", "გასავალი", "გადახდილი", "ხარჯი", "debit", "withdrawal", "paid out", "outflow", "out",
                   "дебет", "расход", "списание" ],
      "credit" => [ "კრედიტი", "შემოსავალი", "ჩარიცხული", "credit", "deposit", "paid in", "inflow", "in",
                    "кредит", "приход", "поступление", "зачисление" ],
      "amount" => [ "თანხა", "amount", "сумма", "sum", "value" ],
      "balance" => [ "ნაშთი", "ბალანსი", "balance", "остаток", "баланс", "running balance" ],
      "currency" => [ "ვალუტა", "currency", "валюта", "ccy", "cur" ],
      "mcc" => [ "mcc", "mcc კოდი", "merchant category", "merchant category code", "мсс" ],
      "transaction_code" => [ "processing code", "proc code", "transaction code", "trn code", "ოპერაციის კოდი", "код операции" ],
      "direction" => [ "d/c", "dr/cr", "debit/credit", "დებეტი/კრედიტი", "direction", "тип" ]
    }.freeze

    def initialize(rows, llm: LLM)
      @rows = rows
      @llm = llm
    end

    # Returns { operations: [...], mapping: {...}, method: "table" }
    def call
      mapping = heuristic_mapping || llm_mapping
      raise ImportError, I18n.t("statements.errors.columns_not_found") unless usable?(mapping)

      operations = @rows.drop(mapping["header_row"] + 1).filter_map { |row| operation_from(row, mapping) }
      raise ImportError, I18n.t("statements.errors.no_operations") if operations.empty?

      { operations: operations, mapping: mapping, metadata: metadata_from_preamble(mapping["header_row"]) }
    end

    private

    def heuristic_mapping
      candidates = @rows.first(HEADER_SCAN_ROWS).each_with_index.map do |row, index|
        [ index, map_header(row) ]
      end
      index, columns = candidates.max_by { |_, cols| cols.size }
      return unless columns && columns.size >= 2

      columns.merge("header_row" => index)
    end

    # Exact matches win over partial ones ("in" must not match "ინფორმაცია")
    def map_header(row)
      columns = {}
      row.each_with_index do |cell, col|
        label = ValueParser.text(cell).downcase
        next if label.blank? || label.length > 60

        field = best_field(label, columns.keys)
        columns[field] = col if field
      end
      columns
    end

    def best_field(label, taken)
      exact = KEYWORDS.find { |field, words| !taken.include?(field) && words.include?(label) }
      return exact.first if exact

      partial = KEYWORDS.find do |field, words|
        !taken.include?(field) && words.any? { |word| word.length > 3 && label.include?(word) }
      end
      partial&.first
    end

    def usable?(mapping)
      mapping.present? && mapping["date"] && (mapping["amount"] || mapping["debit"] || mapping["credit"])
    end

    LLM_SCHEMA = {
      type: "object",
      properties: {
        header_row: { type: "integer", description: "0-based index of the header row" },
        date: { type: [ "integer", "null" ] },
        description: { type: [ "integer", "null" ] },
        counterparty: { type: [ "integer", "null" ] },
        debit: { type: [ "integer", "null" ], description: "column of outgoing amounts" },
        credit: { type: [ "integer", "null" ], description: "column of incoming amounts" },
        amount: { type: [ "integer", "null" ], description: "single signed amount column" },
        balance: { type: [ "integer", "null" ] },
        currency: { type: [ "integer", "null" ] },
        direction: { type: [ "integer", "null" ], description: "column saying debit/credit when amount is unsigned" },
        mcc: { type: [ "integer", "null" ], description: "Merchant Category Code (4 digits)" },
        transaction_code: { type: [ "integer", "null" ], description: "ISO 8583 processing code" }
      },
      required: %w[ header_row date description debit credit amount balance ]
    }.freeze

    def llm_mapping
      sample = @rows.first(25).each_with_index.map do |row, i|
        "row #{i}: " + row.each_with_index.map { |cell, c| "[#{c}] #{ValueParser.text(cell).truncate(40)}" }.join(" | ")
      end.join("\n")

      reply = @llm.chat(format: LLM_SCHEMA, messages: [
        { role: "system", content: "You map the columns of a bank account statement table. Columns are 0-based " \
                                    "indexes shown in brackets. Use null for a field that has no column." },
        { role: "user", content: sample }
      ])
      JSON.parse(reply[:content].to_s).transform_keys(&:to_s).compact
    rescue JSON::ParserError, OllamaChat::Error => e
      Rails.logger.warn "[TableMapper] LLM mapping failed: #{e.message}"
      nil
    end

    def cell(row, mapping, field)
      index = mapping[field]
      index.nil? ? nil : row[index]
    end

    def operation_from(row, mapping)
      date = ValueParser.date(cell(row, mapping, "date"))
      amount = signed_amount(row, mapping)
      return if date.nil? || amount.nil? || amount.zero?

      {
        booked_on: date,
        amount: amount,
        description: ValueParser.text(cell(row, mapping, "description")),
        counterparty: ValueParser.text(cell(row, mapping, "counterparty")).presence,
        balance: ValueParser.amount(cell(row, mapping, "balance")),
        currency: ValueParser.text(cell(row, mapping, "currency")).upcase.presence&.first(3),
        mcc: ValueParser.text(cell(row, mapping, "mcc"))[/\d{4}/],
        transaction_code: ValueParser.text(cell(row, mapping, "transaction_code"))[/\d{2,6}/]
      }.compact
    end

    def signed_amount(row, mapping)
      if mapping["debit"] || mapping["credit"]
        debit = ValueParser.amount(cell(row, mapping, "debit"))&.abs
        credit = ValueParser.amount(cell(row, mapping, "credit"))&.abs
        return credit if credit&.nonzero?
        return -debit if debit&.nonzero?
      end

      amount = ValueParser.amount(cell(row, mapping, "amount"))
      return amount if amount.nil? || mapping["direction"].nil?

      direction = ValueParser.text(cell(row, mapping, "direction")).downcase
      outgoing = direction.match?(/\A(d|dr|debit|დებ|out|withdraw|расход|дебет|-)/)
      outgoing ? -amount.abs : amount.abs
    end

    HOLDER_LABEL = /(?:მფლობელი|კლიენტი|ანგარიშის\s+მფლობელი|account\s+holder|holder|customer|client|владелец|клиент)\s*[:\-]\s*/i
    BANK_LABEL = /(?:ბანკი|bank|банк)\s*[:\-]\s*/i

    # Lines above the table often hold the bank, account holder, account number and currency
    def metadata_from_preamble(header_row)
      cells = @rows.first(header_row).flatten.map { |cell| ValueParser.text(cell) }.compact_blank
      text = cells.join(" ")
      {
        account_number: text[/\bGE\d{2}[A-Z]{2}\d{16}\b/],
        currency: text[/\b(GEL|USD|EUR|GBP|RUB|TRY)\b/, 1],
        account_holder: labelled(cells, HOLDER_LABEL),
        bank_name: labelled(cells, BANK_LABEL)
      }.compact
    end

    # "მფლობელი: გიორგი მაისურაძე" -> "გიორგი მაისურაძე" (stops at the next "label:")
    def labelled(cells, label)
      cells.each do |cell|
        value = cell.split(label, 2)[1] or next
        value = value.split(/\s+\S+:\s/).first.to_s.squish
        return value.truncate(80) if value.present?
      end
      nil
    end
  end
end
