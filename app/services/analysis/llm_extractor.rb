require "base64"

module Analysis
  # Reads operations out of statement text or page images with the LLM's structured output
  # (Ollama "format" = JSON schema). Used for PDFs and scans, where there are no table cells.
  class LLMExtractor
    LINES_PER_CHUNK = 70
    CONTEXT_LINES = 12 # the top of the first page (bank, account, column headers) is sent with each chunk

    SCHEMA = {
      type: "object",
      properties: {
        metadata: {
          type: "object",
          properties: {
            bank_name: { type: [ "string", "null" ] },
            account_holder: { type: [ "string", "null" ] },
            account_number: { type: [ "string", "null" ] },
            currency: { type: [ "string", "null" ], description: "ISO code, e.g. GEL, USD" },
            opening_balance: { type: [ "number", "null" ] },
            closing_balance: { type: [ "number", "null" ] }
          }
        },
        operations: {
          type: "array",
          items: {
            type: "object",
            properties: {
              date: { type: "string", description: "exactly as printed, e.g. 26/05/2026" },
              description: { type: "string" },
              counterparty: { type: [ "string", "null" ] },
              amount: { type: "number", description: "negative = money leaving the account, positive = incoming" },
              currency: { type: [ "string", "null" ] },
              mcc: { type: [ "string", "null" ], description: "4-digit Merchant Category Code, only if printed" },
              balance: { type: [ "number", "null" ], description: "account balance after the operation, if shown" }
            },
            required: %w[ date description amount ]
          }
        }
      },
      required: %w[ metadata operations ]
    }.freeze

    INSTRUCTIONS = <<~TEXT.squish
      You extract bank account operations from a bank statement, exactly as printed. Return every operation row
      in the text, in order; skip headers, page totals, opening/closing balance lines and blank rows. Never invent
      or merge rows. Amounts: money leaving the account (debit, დებეტი, გასული, withdrawal, payment) is negative;
      money coming in (credit, კრედიტი, შემოსული, deposit) is positive. When the statement has one signed amount
      column, copy the sign exactly as printed: a minus means money leaving, no minus means money coming in.
      Copy dates exactly as printed (e.g. 26/05/2026); do not reformat them. Keep descriptions in their original
      language. Fill metadata only from what is printed; use null when absent.
    TEXT

    def initialize(llm: LLM, on_progress: nil)
      @llm = llm
      @on_progress = on_progress
    end

    # pages: array of page strings. Returns { operations:, metadata: }
    def from_text_pages(pages)
      lines = pages.flat_map(&:lines).map(&:rstrip).reject(&:blank?)
      context = lines.first(CONTEXT_LINES).join("\n")
      chunks = lines.each_slice(LINES_PER_CHUNK).to_a

      results = chunks.each_with_index.flat_map do |chunk, i|
        @on_progress&.call(i + 1, chunks.size)
        read_chunk(chunk, context: (context if i.positive?), label: "Part #{i + 1} of #{chunks.size}")
      end

      combine(results)
    end

    # groups: one entry per photo / scanned page, each an array of overlapping strips from ImagePreparer
    # (a single image is accepted too). Rows repeated where strips overlap are removed.
    def from_images(groups)
      groups = groups.map { |group| group.is_a?(Array) ? group : [ group ] }
      total = groups.sum(&:size)
      done = 0
      @unread_parts = 0

      results = groups.map do |strips|
        parts = strips.each_with_index.map do |strip, i|
          @on_progress&.call(done += 1, total)
          read_image(strip, label: strips.size > 1 ? "Image #{i + 1} of #{strips.size} of one statement page" : "A bank statement page")
        end
        { "metadata" => parts.map { |part| part["metadata"].to_h.compact }.reduce({}) { |acc, m| m.merge(acc) },
          "operations" => self.class.merge_strips(parts.map { |part| Array(part["operations"]) }) }
      end
      raise ImportError, I18n.t("statements.errors.photo_unreadable") if @unread_parts == total

      combine(results)
    end

    # Rows at the bottom of one strip can appear again at the top of the next (the strips overlap):
    # drop the longest run of up to 4 rows (same date and amount) repeated across the seam.
    def self.merge_strips(lists)
      key = ->(op) { [ ValueParser.date(op["date"].to_s), ValueParser.amount(op["amount"])&.abs ] }
      lists.each_with_object([]) do |ops, merged|
        overlap = [ 4, merged.size, ops.size ].min.downto(1).find do |k|
          merged.last(k).map(&key) == ops.first(k).map(&key)
        end
        merged.concat(ops.drop(overlap.to_i))
      end
    end

    private

    MIN_SPLIT_LINES = 2
    MAX_IMAGE_SPLITS = 2
    STRIP_PROMPT = "The image is cut into overlapping horizontal strips: extract only the operation rows whose " \
                   "date and amount are fully visible here; skip a row cut off by the top or bottom edge."

    # A strip the model got stuck on is cut in two and read again
    def read_image(bytes, label:, depth: 0)
      result = request([ { role: "user", content: "#{label}. #{STRIP_PROMPT} Extract its operations.",
                           images: [ Base64.strict_encode64(bytes) ] } ])
      return result unless result[:cut]

      if depth < MAX_IMAGE_SPLITS && ImagePreparer.available?
        halves = ImagePreparer.halves(bytes).map { |half| read_image(half, label: label, depth: depth + 1) }
        return { "metadata" => {}, "operations" => self.class.merge_strips(halves.map { |h| Array(h["operations"]) }) }
      end

      Rails.logger.warn "[LLMExtractor] could not read an image part"
      @unread_parts += 1 if depth.zero?
      { "metadata" => {}, "operations" => [] }
    end

    # When the reply is cut (too many rows for num_predict), read each half separately instead of
    # losing the rows of the whole chunk
    def read_chunk(lines, context:, label:)
      prompt = +""
      prompt << "Top of the statement, for context only (do not extract rows from it unless they are in the part below):\n#{context}\n\n" if context
      prompt << "#{label}. Extract the operations from this part:\n#{lines.join("\n")}"
      result = request([ { role: "user", content: prompt } ])
      return [ result ] unless result[:cut] && lines.size >= MIN_SPLIT_LINES

      Rails.logger.info "[LLMExtractor] reply cut, splitting #{lines.size} lines in two"
      lines.each_slice((lines.size / 2.0).ceil).flat_map { |half| read_chunk(half, context: context, label: label) }
    end

    def request(messages)
      reply = @llm.chat(format: SCHEMA, messages: [ { role: "system", content: INSTRUCTIONS } ] + messages)
      return { cut: true } if reply[:done_reason] == "length"

      JSON.parse(reply[:content].to_s)
    rescue OllamaChat::Error => e
      raise unless e.message.match?(/repeat limit|prediction aborted/i) # Ollama stopped a looping reply

      Rails.logger.warn "[LLMExtractor] #{e.message}"
      { cut: true }
    rescue JSON::ParserError => e
      Rails.logger.warn "[LLMExtractor] invalid JSON from the model: #{e.message}"
      { "metadata" => {}, "operations" => [] }
    end

    def combine(results)
      results = results.reject { |r| r[:cut] } # a cut reply that could not be split further
      metadata = results.map { |r| r["metadata"].to_h.compact }.reduce({}) { |acc, m| m.merge(acc) }
      metadata["closing_balance"] = results.reverse.map { |r| r.dig("metadata", "closing_balance") }.compact.first
      operations = results.flat_map { |r| Array(r["operations"]) }.filter_map { |op| normalize(op) }

      { operations: operations, metadata: metadata.compact.symbolize_keys }
    end

    def normalize(op)
      date = ValueParser.date(op["date"].to_s)
      amount = ValueParser.amount(op["amount"])
      return if date.nil? || amount.nil? || amount.zero?

      {
        booked_on: date,
        amount: amount,
        description: op["description"].to_s.squish,
        counterparty: op["counterparty"].to_s.squish.presence,
        balance: ValueParser.amount(op["balance"]),
        currency: op["currency"].to_s.upcase.presence&.first(3),
        mcc: op["mcc"].to_s[/\d{4}/]
      }.compact
    end
  end
end
