# app/services/ollama_chat.rb
require "net/http"

# Thin client for the local Ollama native chat API (POST /api/chat).
# We use the native endpoint (not the OpenAI-compatible /v1) because only it
# accepts per-request options such as num_ctx.
class OllamaChat
  class Error < StandardError; end

  DEFAULT_URL = "http://localhost:11434"
  DEFAULT_MODEL = "gemma4:12b"
  DEFAULT_NUM_CTX = 262_144 # gemma4:12b max; fits fully on the RTX 5070
  DEFAULT_NUM_PREDICT = 6144

  def initialize(base_url: ENV.fetch("OLLAMA_URL", DEFAULT_URL), read_timeout: 600)
    @base_url = base_url
    @read_timeout = read_timeout
  end

  # messages: [{ role: "system"|"user"|"assistant"|"tool", content: "..." }]
  # tools: [{ type: "function", function: { name: "...", description: "...", parameters: {...} } }]
  # format: a JSON schema (or "json") to force structured output; the reply's content is then JSON.
  # Images go inside a message: { role: "user", content: "...", images: [base64, ...] } (gemma4 has vision).
  # Returns the assistant message hash: { role:, content:, tool_calls: [...], thinking: }
  # num_predict caps the reply length: without it a model stuck in a repetition loop keeps
  # generating until the whole context is full (minutes at 64k).
  def chat(messages:, model: DEFAULT_MODEL, tools: nil, num_ctx: DEFAULT_NUM_CTX, temperature: nil, think: nil,
           format: nil, num_predict: DEFAULT_NUM_PREDICT)
    body = {
      model: model,
      messages: messages,
      stream: false,
      options: { num_ctx: num_ctx, num_predict: num_predict }
    }
    body[:options][:temperature] = temperature if temperature
    body[:tools] = tools if tools.present?
    body[:think] = think unless think.nil?
    body[:format] = format if format

    data = post("/api/chat", body)
    Rails.logger.info "[Ollama] #{data[:eval_count]} tokens in #{(data[:total_duration].to_f / 1e9).round(1)}s (#{data[:done_reason]})"
    Rails.logger.warn "[Ollama] reply cut at num_predict=#{num_predict} (model looping?)" if data[:done_reason] == "length"
    data[:message]
  end

  private

  def post(path, body)
    uri = URI.join(@base_url, path)
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: @read_timeout) do |http|
      http.post(uri.path, body.to_json, "Content-Type" => "application/json")
    end

    data = JSON.parse(response.body, symbolize_names: true)
    raise Error, "Ollama API error: #{data[:error] || response.code}" unless response.is_a?(Net::HTTPSuccess)

    data
  rescue JSON::ParserError
    raise Error, "Ollama returned invalid JSON (HTTP #{response&.code})"
  rescue Net::ReadTimeout
    raise Error, "Ollama did not answer within #{@read_timeout}s"
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout => e
    raise Error, "Cannot reach Ollama at #{@base_url} (#{e.class}). Is the ollama service running?"
  end
end
