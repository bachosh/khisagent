module Statements
  # File → operations in the database.
  #   CSV / XLSX / XLS → TableReader + TableMapper (LLM only to map unusual headers)
  #   text PDF          → pdftotext + LLMExtractor
  #   scanned PDF/image → page images + LLMExtractor (gemma4 vision)
  # Then every operation is categorized (stage I, config/bank_codes.yml).
  class Importer
    MAX_IMAGE_BYTES = 15.megabytes

    def initialize(statement, llm: LLM)
      @statement = statement
      @llm = llm
    end

    def call
      result = @statement.file.open { |file| extract(file.path) }
      operations = result[:operations]
      raise ImportError, I18n.t("statements.errors.no_operations") if operations.empty?

      save(operations, result[:metadata].to_h, result[:mapping])
    end

    private

    def extract(path)
      case @statement.file_kind
      when "csv", "xlsx", "xls" then from_table(path)
      when "pdf" then from_pdf(path)
      when "image" then from_image(path)
      end
    end

    def from_table(path)
      progress("reading")
      rows = TableReader.call(path, @statement.file_kind)
      raise ImportError, I18n.t("statements.errors.empty_file") if rows.empty?

      @statement.update!(extraction_method: "table")
      TableMapper.new(rows, llm: @llm).call
    end

    def from_pdf(path)
      reader = PdfReader.new(path)
      raise ImportError, I18n.t("statements.errors.too_many_pages", max: PdfReader::MAX_PAGES) if reader.page_count > PdfReader::MAX_PAGES

      if reader.scanned?
        @statement.update!(extraction_method: "vision")
        images = []
        reader.each_page_image { |png| images << png }
        extractor.from_images(images)
      else
        @statement.update!(extraction_method: "pdf_text")
        extractor.from_text_pages(reader.text_pages)
      end
    end

    def from_image(path)
      raise ImportError, I18n.t("statements.errors.image_too_large") if File.size(path) > MAX_IMAGE_BYTES

      @statement.update!(extraction_method: "vision")
      extractor.from_images([ File.binread(path) ])
    end

    def extractor
      LLMExtractor.new(llm: @llm, on_progress: ->(part, total) { progress("extracting_part", part: part, total: total) })
    end

    def progress(key, **args)
      @statement.progress!(status: "extracting", note: I18n.t("statements.progress.#{key}", **args))
    end

    def save(rows, metadata, mapping)
      progress("categorizing")
      currency = metadata[:currency].presence || rows.filter_map { |r| r[:currency] }.tally.max_by(&:last)&.first

      Statement.transaction do
        @statement.operations.delete_all
        records = rows.each_with_index.map do |row, i|
          codes = Categorizer.call(description: row[:description], counterparty: row[:counterparty], amount: row[:amount],
                                   mcc: row[:mcc], transaction_code: row[:transaction_code])
          row.merge(codes).merge(statement_id: @statement.id, position: i + 1, currency: row[:currency] || currency)
        end
        Operation.insert_all!(records.map { |r| normalize_keys(r) })

        dates = rows.filter_map { |r| r[:booked_on] }
        @statement.update!(
          column_mapping: mapping,
          operations_count: records.size,
          period_start: dates.min,
          period_end: dates.max,
          currency: currency,
          bank_name: metadata[:bank_name].presence || @statement.bank_name,
          account_holder: metadata[:account_holder].presence || @statement.account_holder,
          account_number: metadata[:account_number].presence || @statement.account_number,
          opening_balance: ValueParser.amount(metadata[:opening_balance]),
          closing_balance: ValueParser.amount(metadata[:closing_balance])
        )
      end
    end

    COLUMNS = %i[ statement_id position booked_on description counterparty amount currency balance mcc
                  transaction_code category category_group ].freeze

    # insert_all needs the same keys in every row
    def normalize_keys(row)
      COLUMNS.index_with { |key| row[key] }.merge(description: row[:description].to_s)
    end
  end
end
