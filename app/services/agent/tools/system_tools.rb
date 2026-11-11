# app/services/agent/tools/system_tools.rb
module Agent
  module Tools
    # Universal tools, not tied to any domain. Every agent should register these.
    class SystemTools
      def self.register_all
        register_terminate
        register_ask_user
        register_think
      end

      # The way an agent finishes its work
      def self.register_terminate
        ToolRegistry.register(
          "terminate",
          lambda do |message:|
            message
          end,
          description: "Terminates the agent's execution with a final message or result. " \
                      "This MUST be called when the agent has completed its task. " \
                      "The message parameter should contain the final answer, summary, or output " \
                      "that the user requested. This is how the agent signals completion.",
          parameters: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "The final result, answer, or summary to return to the user"
              }
            },
            required: [ "message" ]
          },
          terminal: true,
          tags: [ "system", "control", "terminal" ]
        )
      end

      # Asks on the terminal when running in an interactive console; otherwise says no one is there
      def self.register_ask_user
        ToolRegistry.register(
          "ask_user",
          lambda do |question:|
            if $stdin.tty?
              print "\n[Agent asks] #{question}\n> "
              { answer: $stdin.gets.to_s.strip }
            else
              { answer: nil, note: "No user is available to answer. Make a reasonable assumption and continue." }
            end
          end,
          description: "Ask the user a question when you need clarification or additional information. " \
                      "Use this only when the task is ambiguous and you cannot continue without an answer. " \
                      "The question should be clear and specific.",
          parameters: {
            type: "object",
            properties: {
              question: {
                type: "string",
                description: "The question to ask the user. Be specific and clear."
              }
            },
            required: [ "question" ]
          },
          tags: [ "system", "interaction", "user" ]
        )
      end

      # Tagged "debug", not "system": local models with built-in thinking spend
      # whole turns on this tool, so agents opt in by selecting the "debug" tag.
      def self.register_think
        ToolRegistry.register(
          "think",
          lambda do |thoughts:|
            Rails.logger.info "[Agent Thinking] #{thoughts}"
            { recorded: true }
          end,
          description: "Record your internal thoughts and reasoning process. " \
                      "Use this to plan next steps or note important observations. " \
                      "This does not affect execution but provides insight into the agent's reasoning.",
          parameters: {
            type: "object",
            properties: {
              thoughts: {
                type: "string",
                description: "Your internal reasoning, observations, or plans"
              }
            },
            required: [ "thoughts" ]
          },
          tags: [ "debug", "logging" ]
        )
      end
    end
  end
end
