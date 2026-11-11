# app/services/agent/memory.rb
module Agent
  # Conversation memory (the M in GAME)
  #
  # Items:
  #   { type: "user",        content: "..." }
  #   { type: "assistant",   content: "...", tool_calls: [...] }
  #   { type: "environment", content: "<result json>", tool_name: "..." }
  #   { type: "system",      content: "..." }
  class Memory
    attr_accessor :items

    def initialize
      @items = []
    end

    def add_memory(memory)
      @items << memory
    end

    # limit: the N most recent items
    def get_memories(limit: nil)
      limit ? @items.last(limit) : @items
    end

    def copy_without_system_memories
      memory = Memory.new
      memory.items = @items.reject { |m| m[:type] == "system" }
      memory
    end

    # The result of the last executed tool (normally the terminal one)
    def final_output
      last = @items.reverse.find { |m| m[:type] == "environment" }
      return unless last

      result = JSON.parse(last[:content])
      result["tool_executed"] ? result["result"] : result["error"]
    end
  end
end
