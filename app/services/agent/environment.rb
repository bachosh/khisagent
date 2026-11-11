# app/services/agent/environment.rb
module Agent
  # Execution environment (the E in GAME)
  # Errors are returned to the LLM instead of raised, so it can recover.
  class Environment
    def execute_action(action, args)
      result = action.execute(**args.to_h.symbolize_keys)
      format_result(result)
    rescue StandardError => e
      Rails.logger.error "[Agent] #{action.name} failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
      { tool_executed: false, error: "#{e.class}: #{e.message}" }
    end

    def format_result(result)
      { tool_executed: true, result: result }
    end
  end
end
