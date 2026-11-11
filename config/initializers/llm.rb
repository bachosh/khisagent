# Settings for the local Ollama model used by every agent in this app.
#
# One num_ctx for all requests on purpose: Ollama reloads the model whenever num_ctx changes,
# so mixing sizes (e.g. extraction at 32k, agent at 256k) would reload it on every switch.
# 64k fits gemma4:12b fully in 12 GB VRAM at ~170 tok/s (256k works too, at ~41 tok/s).
Rails.application.config.x.llm = ActiveSupport::OrderedOptions.new.tap do |llm|
  llm.model = ENV.fetch("OLLAMA_MODEL", "gemma4:12b")
  llm.num_ctx = ENV.fetch("OLLAMA_NUM_CTX", 65_536).to_i
  # Max tokens per reply (thinking included). Stops a looping model from filling the whole context.
  llm.num_predict = ENV.fetch("OLLAMA_NUM_PREDICT", 6144).to_i
end
