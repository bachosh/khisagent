require "csv"

module Statements
  # Reads CSV / XLSX / XLS files into rows of cell values (String, Numeric or Date).
  # For workbooks it picks the sheet with the most rows.
  class TableReader
    MAX_ROWS = 50_000

    def self.call(path, kind)
      new(path, kind).rows
    end

    def initialize(path, kind)
      @path = path
      @kind = kind
    end

    def rows
      rows = @kind == "csv" ? csv_rows : workbook_rows
      rows.first(MAX_ROWS).reject { |row| row.all? { |cell| cell.to_s.strip.empty? } }
    end

    private

    def csv_rows
      text = read_text
      CSV.parse(text, col_sep: detect_separator(text), liberal_parsing: true)
    rescue CSV::MalformedCSVError => e
      raise ImportError, "CSV: #{e.message}"
    end

    # UTF-8 (with or without BOM), else Windows-1251 (old Russian-language exports)
    def read_text
      raw = File.binread(@path)
      raw = raw.byteslice(3..) if raw.start_with?("\xEF\xBB\xBF".b)
      text = raw.dup.force_encoding(Encoding::UTF_8)
      return text if text.valid_encoding?

      raw.encode(Encoding::UTF_8, Encoding::Windows_1251, invalid: :replace, undef: :replace)
    end

    def detect_separator(text)
      sample = text.lines.first(20).join
      [ ",", ";", "\t", "|" ].max_by { |sep| sample.count(sep) }
    end

    def workbook_rows
      book = @kind == "xls" ? Roo::Excel.new(@path) : Roo::Excelx.new(@path)
      sheet = book.sheets.max_by { |name| book.sheet(name).last_row.to_i }
      book.default_sheet = sheet
      return [] unless book.first_row

      (book.first_row..book.last_row).map { |i| book.row(i) }
    rescue Zip::Error, Ole::Storage::FormatError, ArgumentError => e
      raise ImportError, "#{@kind.upcase}: #{e.message}"
    end
  end
end
