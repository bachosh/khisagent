require "base64"

module Statements
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
              date: { type: "string", description: "YYYY-MM-DD" },
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
      or merge rows. Amounts: money leaving the account (debit, დებეტი, withdrawal, payment) is negative; money
      coming in (credit, კრედიტი, deposit) is positive. Dates as YYYY-MM-DD (statements in Georgia write day first:
      03.01.2026 is 3 January). Keep descriptions in their original language. Fill metadata only from what is
      printed; use null when absent.
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

      results = chunks.each_with_index.map do |chunk, i|
        @on_progress&.call(i + 1, chunks.size)
        prompt = +""
        prompt << "Top of the statement, for context only (do not extract rows from it unless they are in the part below):\n#{context}\n\n" if i.positive?
        prompt << "Part #{i + 1} of #{chunks.size}. Extract the operations from this part:\n#{chunk.join("\n")}"
        request([ { role: "user", content: prompt } ])
      end

      combine(results)
    end

    # images: array of PNG/JPEG bytes (one per page)
    def from_images(images)
      results = images.each_with_index.map do |bytes, i|
        @on_progress&.call(i + 1, images.size)
        request([ { role: "user", content: "Page #{i + 1} of #{images.size} of a bank statement. Extract its operations.",
                    images: [ Base64.strict_encode64(bytes) ] } ])
      end

      combine(results)
    end

    private

    def request(messages)
      reply = @llm.chat(format: SCHEMA, messages: [ { role: "system", content: INSTRUCTIONS } ] + messages)
      JSON.parse(reply[:content].to_s)
    rescue JSON::ParserError => e
      Rails.logger.warn "[LLMExtractor] invalid JSON from the model: #{e.message}"
      { "metadata" => {}, "operations" => [] }
    end

    def combine(results)
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
