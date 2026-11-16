module Analysis
  # Reads operations straight from `pdftotext -layout` text, without the LLM. Bank PDFs print a table:
  #
  #   თარიღი       დანიშნულება                                   GEL      USD   EUR      GBP
  #   11/05/2026   საწყისი ნაშთი:                                 10       0      0       0.00
  #   11/05/2026   გადახდა - თანხა: GEL30.00; ობიექტი: Socar,     -30.0
  #                MCC:5541; თარიღი: 11/05/2026 21:02; ...
  #
  # An operation starts with a date; the next indented lines continue its description. Amounts are matched
  # to columns by their position under the header labels: currency columns (GEL, USD...) hold signed
  # amounts, debit/credit columns unsigned ones, plus amount and balance columns.
  #
  # Known to work with Bank of Georgia (currency columns, balances in a dated row above the table) and
  # TBC (გასული / შემოსული / ბალანსი columns that shift per page, balances in undated summary lines).
  #
  # Returns nil when the layout is not recognized or rows can't be read, so the caller falls back to
  # LLMExtractor. The result is checked afterwards by Reconciler (opening + operations = closing).
  class PdfLayoutParser
    DATE = %r{\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{4}-\d{2}-\d{2}}
    ROW_START = /\A\s{0,4}(#{DATE})(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?\s+(.*)\z/
    CURRENCIES = %w[ GEL USD EUR GBP RUB TRY CHF ].freeze
    DATE_LABELS = [ "თარიღი", "date", "дата", "datum" ].freeze
    OPENING = /საწყისი\s+ნაშთი|opening\s+balance|начальн\w*\s+остат|incoming\s+balance/i
    CLOSING = /საბოლოო\s+ნაშთი|closing\s+balance|конечн\w*\s+остат|outgoing\s+balance/i
    NUMBER = /\A[-−(]?\d[\d\s,.]*\)?-?\z/
    SUMMARY_BALANCE = /\A\s*(?<label>.*?(?:#{OPENING.source}|#{CLOSING.source}).*?)[:\s]{2,}(?<amount>-?\d[\d ,.]*\d|\d)\s?(?<currency>[A-Z]{3})?(?:\s{2,}.*)?\z/i
    MAX_COLUMN_DISTANCE = 8
    MIN_PARSED_SHARE = 0.98

    Column = Struct.new(:kind, :currency, :from, :to) # kind: currency | debit | credit | amount | balance

    def initialize(pages)
      @lines = pages.flat_map { |page| page.lines.map(&:rstrip) }
    end

    # => { operations: [...], metadata: { opening: {"GEL"=>10}, closing: {...}, account_holder:, ... } } or nil
    def call
      header_index = @lines.index { |line| header_columns(line) }
      return unless header_index

      @columns = header_columns(@lines[header_index])
      @description_col = description_column(@lines[header_index])
      rows = collect_rows(header_index)
      operation_rows = rows.reject { |row| row[:balance_line] }
      return if operation_rows.empty?

      operations = operation_rows.filter_map { |row| build_operation(row) }
      return if operations.size < operation_rows.size * MIN_PARSED_SHARE

      { operations: operations, metadata: metadata(header_index) }
    end

    private

    # Splits a line into [text, start, end] segments separated by 2+ spaces
    def segments(line)
      line.to_enum(:scan, /\S+(?: \S+)*/).map { [ Regexp.last_match[0], Regexp.last_match.begin(0), Regexp.last_match.end(0) ] }
    end

    # Columns of the table header (must have a date label); with require_date: false also a bare
    # "GEL  USD  EUR" line, like the one above the opening/closing balances of Bank of Georgia statements
    def header_columns(line, require_date: true)
      cells = segments(line)
      return if require_date && cells.none? { |text, *| DATE_LABELS.include?(text.downcase) }

      columns = cells.filter_map do |text, from, to|
        label = text.downcase
        if CURRENCIES.include?(text.upcase) && text.length == 3
          Column.new("currency", text.upcase, from, to)
        elsif (kind = amount_kind(label))
          Column.new(kind, nil, from, to)
        end
      end
      columns.presence
    end

    def amount_kind(label)
      %w[ debit credit amount balance ].find { |kind| TableMapper::KEYWORDS[kind].include?(label) }
    end

    def description_column(header)
      second = segments(header).find { |text, *| !DATE_LABELS.include?(text.downcase) }
      second ? second[1] : 12
    end

    def zone_start(columns)
      columns.map(&:from).min - MAX_COLUMN_DISTANCE - 4
    end

    # Column positions can shift from page to page (TBC), so each repeated header sets the columns
    # for the rows below it
    def collect_rows(header_index)
      rows = []
      current = nil
      columns = @columns
      @lines[header_index..].each do |line|
        if (header = header_columns(line))
          columns = header
          current = nil
        elsif (match = line.match(ROW_START))
          current = { date: match[1], lines: [ line ], balance_line: balance_kind(match[2]), columns: columns,
                      indent: [ match.begin(2), @description_col ].min - 3 }
          rows << current
        elsif line.strip.empty?
          current = nil # a blank line ends the operation
        elsif current && line.index(/\S/).to_i >= current[:indent] # wrapped description (TBC: right after the date)
          current[:lines] << line
        end
      end
      rows
    end

    def balance_kind(text)
      return :opening if text.match?(OPENING)

      :closing if text.match?(CLOSING)
    end

    # Numbers that sit under an amount column, from the first line of the row (or a continuation line)
    def amounts(row, columns = row[:columns] || @columns)
      row[:lines].each do |line|
        found = amount_tokens(line, columns).map { |column, value, *| [ column, value ] }
        return found if found.any?
      end
      []
    end

    # [column, value, from, to] for each number under an amount column. A number can be glued to the
    # text before it by a single space when that text is long (TBC's "additional information" column).
    def amount_tokens(line, columns)
      start = zone_start(columns)
      segments(line).filter_map do |text, from, to|
        next if to < start

        unless text.match?(NUMBER)
          last = text[/\s(\S+)\z/, 1] or next
          next unless last.match?(NUMBER) && last.match?(/\d[.,]\d{1,2}\)?\z/) # only clear amounts like 9.99

          from = to - last.length
          next if from < start
          text = last
        end
        column = nearest_column(from, to, columns) or next
        value = ValueParser.amount(text)
        [ column, value, from, to ] if value
      end
    end

    def nearest_column(from, to, columns = @columns)
      distance = ->(col) { to < col.from ? col.from - to : (from > col.to ? from - col.to : 0) }
      best = columns.min_by(&distance)
      best if distance.(best) <= MAX_COLUMN_DISTANCE
    end

    def build_operation(row)
      date = ValueParser.date(row[:date])
      found = amounts(row)
      balance = found.find { |col, _| col.kind == "balance" }&.last
      signed = found.filter_map do |col, value|
        case col.kind
        when "currency", "amount" then [ value, col.currency ]
        when "credit" then [ value.abs, nil ]
        when "debit" then [ -value.abs, nil ]
        end
      end.reject { |value, _| value.zero? }
      return if date.nil? || signed.size != 1

      amount, currency = signed.first
      {
        booked_on: date,
        amount: amount,
        currency: currency,
        balance: balance,
        description: description(row)
      }.compact
    end

    # The row's text without the amounts, joined across its lines, without the leading date
    def description(row)
      columns = row[:columns] || @columns
      row[:lines].map.with_index do |line, i|
        text = line.dup
        amount_tokens(line, columns).each { |*, from, to| text[from...to] = " " * (to - from) }
        text = text.sub(ROW_START) { Regexp.last_match[2] } if i.zero?
        text.squish
      end.reject(&:empty?).join(" ").squish
    end

    def metadata(header_index)
      {
        opening: balances(:opening),
        closing: balances(:closing),
        **StatementHeader.from_lines(@lines[0...header_index])
      }.compact_blank
    end

    # Opening / closing balance per currency ("*" for a single balance column). The balance lines may
    # sit above the table, under their own currency header, so they are searched in the whole text.
    def balances(kind)
      summary_balance(kind) || dated_balance(kind)
    end

    # "საწყისი ნაშთი          1234.56 GEL" (TBC prints these above the table, without a date)
    def summary_balance(kind)
      @lines.each do |line|
        next if line.match?(ROW_START)

        match = line.match(SUMMARY_BALANCE) or next
        next unless balance_kind(match[:label]) == kind

        value = ValueParser.amount(match[:amount])
        return { (match[:currency]&.upcase || "*") => value } if value
      end
      nil
    end

    def dated_balance(kind)
      index = @lines.index { |line| (m = line.match(ROW_START)) && balance_kind(m[2]) == kind } or return
      columns = columns_above(index) || @columns
      amounts({ lines: [ @lines[index] ] }, columns).each_with_object({}) do |(col, value), result|
        result[col.currency || "*"] = value if %w[ currency balance amount ].include?(col.kind)
      end.presence
    end

    def columns_above(index)
      (index - 1).downto([ index - 15, 0 ].max) do |i|
        columns = header_columns(@lines[i], require_date: false)
        return columns if columns
      end
      nil
    end
  end
end
