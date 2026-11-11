# app/services/agent/prompt.rb
module Agent
  # Prompt structure sent to the LLM
  class Prompt
    attr_accessor :messages, :tools, :metadata

    def initialize(messages: [], tools: [], metadata: {})
      @messages = messages
      @tools = tools
      @metadata = metadata
    end
  end
end
