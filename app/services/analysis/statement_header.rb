module Analysis
  # Facts printed above a statement's table (CSV/XLSX preamble rows, PDF header lines):
  # account holder, bank, account number (IBAN) and currency.
  module StatementHeader
    module_function

    HOLDER_LABEL = /(?:ანგარიშის\s+მფლობელი|მფლობელი|კლიენტი|account\s+holder|holder|customer|client|владелец|клиент)\s*[:\-]\s*/i
    BANK_LABEL = /(?:ბანკი|bank|банк)\s*[:\-]\s*/i
    IBAN = /\bGE\d{2}([A-Z]{2})\d{16}\b/

    # cells: strings, e.g. the preamble cells of a table or the lines above a PDF table
    def from_lines(cells)
      cells = cells.map { |cell| cell.to_s.squish }.reject(&:empty?)
      text = cells.join(" ")
      iban = text[IBAN]
      {
        account_number: iban,
        account_holder: labelled(cells, HOLDER_LABEL),
        bank_name: labelled(cells, BANK_LABEL) || (iban && BankCodes.bank_for_iban(iban)),
        currency: text[/\b(GEL|USD|EUR|GBP|RUB|TRY)\b/, 1]
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
