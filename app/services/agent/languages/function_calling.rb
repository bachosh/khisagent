# app/services/agent/languages/function_calling.rb
module Agent
  module Languages
    # Native tool calling, in the Ollama /api/chat message format
    class FunctionCalling < Base
      SEPARATOR = "\n-------------------\n"

      def format_goals(goals)
        goal_instructions = goals.sort_by(&:priority).map do |goal|
          "#{goal.name}:#{SEPARATOR}#{goal.description}#{SEPARATOR}"
        end.join("\n\n")

        [ { role: "system", content: goal_instructions } ]
      end

      def format_memory(memory)
        memory.get_memories.map do |item|
          case item[:type]
          when "assistant"
            message = { role: "assistant", content: item[:content].to_s }
            message[:tool_calls] = item[:tool_calls] if item[:tool_calls].present?
            message
          when "environment"
            { role: "tool", tool_name: item[:tool_name], content: item[:content] }
          when "system"
            { role: "system", content: item[:content] }
          else
            { role: "user", content: item[:content] }
          end
        end
      end

      def format_actions(actions)
        actions.map do |action|
          {
            type: "function",
            function: {
              name: action.name,
              description: action.description.to_s.slice(0, 1024),
              parameters: action.parameters
            }
          }
        end
      end

      def construct_prompt(actions:, environment:, goals:, memory:)
        messages = format_goals(goals) + format_memory(memory)
        Agent::Prompt.new(messages: messages, tools: format_actions(actions))
      end

      # Returns every tool call the model made (models can call several at once).
      # A plain-text answer with no tool calls is treated as the final answer.
      def parse_response(response)
        tool_calls = Array(response[:tool_calls])

        if tool_calls.empty?
          return [ { tool: "terminate", args: { message: response[:content].to_s } } ]
        end

        tool_calls.map do |tool_call|
          arguments = tool_call.dig(:function, :arguments) || {}
          # Ollama returns an object; OpenAI-style APIs return a JSON string
          arguments = JSON.parse(arguments) if arguments.is_a?(String)

          { tool: tool_call.dig(:function, :name), args: arguments }
        end
      end
    end
  end
end
