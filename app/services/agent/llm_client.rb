# app/services/agent/llm_client.rb
module Agent
  # Wrapper for local Ollama LLM calls
  class LLMClient
    attr_reader :model

    # think: true/false turns the model's built-in reasoning on/off; nil = model default
    def initialize(ollama_chat: nil, model: OllamaChat::DEFAULT_MODEL, num_ctx: OllamaChat::DEFAULT_NUM_CTX,
                   temperature: nil, think: nil, num_predict: OllamaChat::DEFAULT_NUM_PREDICT)
      @ollama_chat = ollama_chat || OllamaChat.new
      @model = model
      @num_ctx = num_ctx
      @temperature = temperature
      @think = think
      @num_predict = num_predict
    end

    # Returns the assistant message hash: { content:, tool_calls:, thinking: }
    def call(prompt)
      @ollama_chat.chat(
        messages: prompt.messages,
        tools: prompt.tools,
        model: @model,
        num_ctx: @num_ctx,
        temperature: @temperature,
        think: @think,
        num_predict: @num_predict
      )
    end
  end
end
