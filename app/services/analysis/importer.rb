module Analysis
  # File → operations in the database.
  #   CSV / XLSX / XLS → TableReader + TableMapper (LLM only to map unusual headers)
  #   text PDF          → pdftotext + PdfLayoutParser (no LLM, ~1s); LLMExtractor only when the layout is unknown
  #                        or the parsed totals don't reconcile
  #   scanned PDF/image → page images + LLMExtractor (gemma4 vision)
  # Then every operation is categorized (stage I, config/bank_codes.yml) and the import is checked
  # by Reconciler (opening + operations = closing balance), shown on the report.
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

      metadata = result[:metadata].to_h
      reconciliation = result[:reconciliation] || reconcile(operations, metadata)
      save(operations, metadata, result[:mapping], reconciliation)
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
      progress("reading")
      reader.scanned? ? from_scan(reader) : from_pdf_text(reader)
    end

    def from_pdf_text(reader)
      check_pages(reader, PdfReader::MAX_TEXT_PAGES)
      pages = reader.text_pages

      parsed = PdfLayoutParser.new(pages).call
      if parsed
        parsed[:reconciliation] = reconcile(parsed[:operations], parsed[:metadata])
        @statement.update!(extraction_method: "pdf_layout")
        return parsed unless parsed[:reconciliation][:status] == "mismatch"
      end

      # Unknown layout, or the totals don't add up: let the LLM read the text
      @statement.update!(extraction_method: "pdf_text")
      by_llm = extractor.from_text_pages(pages)
      by_llm[:reconciliation] = reconcile(by_llm[:operations], by_llm[:metadata])
      parsed ? closer(parsed, by_llm) : by_llm
    end

    def from_scan(reader)
      check_pages(reader, PdfReader::MAX_SCAN_PAGES)
      @statement.update!(extraction_method: "vision")
      pages = []
      reader.each_page_image { |png| pages << ImagePreparer.strips(png) }
      extractor.from_images(pages)
    end

    def check_pages(reader, max)
      raise ImportError, I18n.t("statements.errors.too_many_pages", max: max) if reader.page_count > max
    end

    # Both readings disagree with the printed balances: keep the one closer to them
    def closer(parsed, by_llm)
      return by_llm if by_llm[:reconciliation][:status] == "ok"

      chosen = [ parsed, by_llm ].min_by { |r| r[:reconciliation][:difference].to_d.abs }
      @statement.update!(extraction_method: chosen.equal?(parsed) ? "pdf_layout" : "pdf_text")
      chosen
    end

    # Opening/closing balances come per currency from PdfLayoutParser ({ "GEL" => 10 }),
    # as single values from LLMExtractor (opening_balance: 10)
    def reconcile(operations, metadata)
      opening = metadata[:opening] || single_balance(metadata[:opening_balance])
      closing = metadata[:closing] || single_balance(metadata[:closing_balance])
      Reconciler.call(operations, opening: opening, closing: closing)
    end

    def single_balance(value)
      amount = ValueParser.amount(value)
      amount ? { "*" => amount } : nil
    end

    def from_image(path)
      raise ImportError, I18n.t("statements.errors.image_too_large") if File.size(path) > MAX_IMAGE_BYTES

      @statement.update!(extraction_method: "vision")
      extractor.from_images([ ImagePreparer.strips(File.binread(path)) ])
    end

    def extractor
      LLMExtractor.new(llm: @llm, on_progress: ->(part, total) { progress("extracting_part", part: part, total: total) })
    end

    def progress(key, **args)
      @statement.progress!(status: "extracting", note: I18n.t("statements.progress.#{key}", **args))
    end

    def save(rows, metadata, mapping, reconciliation)
      progress("categorizing")
      currency = rows.filter_map { |r| r[:currency] }.tally.max_by(&:last)&.first || metadata[:currency].presence

      Analysis::Statement.transaction do
        @statement.operations.delete_all
        records = rows.each_with_index.map do |row, i|
          codes = Categorizer.call(description: row[:description], counterparty: row[:counterparty], amount: row[:amount],
                                   mcc: row[:mcc], transaction_code: row[:transaction_code])
          row.merge(codes).merge(statement_id: @statement.id, position: i + 1, currency: row[:currency] || currency)
        end
        Analysis::Operation.insert_all!(records.map { |r| normalize_keys(r) })

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
          opening_balance: balance_in(metadata[:opening], currency) || ValueParser.amount(metadata[:opening_balance]),
          closing_balance: balance_in(metadata[:closing], currency) || ValueParser.amount(metadata[:closing_balance]),
          reconciliation: reconciliation[:status],
          reconciliation_difference: reconciliation[:difference]
        )
      end
    end

    def balance_in(balances, currency)
      return unless balances

      balances[currency] || balances["*"]
    end

    COLUMNS = %i[ statement_id position booked_on description counterparty amount currency balance mcc
                  transaction_code category category_group ].freeze

    # insert_all needs the same keys in every row
    def normalize_keys(row)
      COLUMNS.index_with { |key| row[key] }.merge(description: row[:description].to_s)
    end
  end
end
