# Factory for the app's LLM clients, so every caller uses the same model and context size
module LLM
  def self.config
    Rails.application.config.x.llm
  end

  # think: nil = model default (gemma4 reasons before answering), false = answer directly
  def self.agent_client(think: nil, temperature: nil)
    Agent::LLMClient.new(model: config.model, num_ctx: config.num_ctx, think: think, temperature: temperature,
                         num_predict: config.num_predict)
  end

  # Structured extraction (JSON schema output) without the agent loop
  def self.chat(messages:, format: nil, think: false, temperature: 0)
    OllamaChat.new(read_timeout: 300).chat(messages: messages, format: format, model: config.model,
                                           num_ctx: config.num_ctx, think: think, temperature: temperature,
                                           num_predict: config.num_predict)
  end
end
