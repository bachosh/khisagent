# app/services/agent/runner.rb
module Agent
  # Runs the agent loop: prompt -> LLM decides -> execute tools -> remember -> repeat
  class Runner
    attr_reader :goals, :action_registry, :environment, :agent_language, :llm_client

    def initialize(goals:, agent_language:, action_registry:, llm_client:, environment: nil)
      @goals = goals
      @agent_language = agent_language
      @action_registry = action_registry
      @llm_client = llm_client
      @environment = environment || Environment.new
    end

    def construct_prompt(goals, memory, action_registry)
      @agent_language.construct_prompt(
        actions: action_registry.get_actions,
        environment: @environment,
        goals: goals,
        memory: memory
      )
    end

    def set_current_task(memory, task)
      memory.add_memory({ type: "user", content: task })
    end

    def update_memory(memory, response, results)
      memory.add_memory({ type: "assistant", content: response[:content].to_s, tool_calls: response[:tool_calls] })
      results.each do |tool_name, result|
        memory.add_memory({ type: "environment", tool_name: tool_name, content: result.to_json })
      end
    end

    def prompt_llm_for_action(prompt)
      @llm_client.call(prompt)
    end

    def execute_invocation(invocation)
      action = @action_registry.get_action(invocation[:tool])

      unless action
        available = @action_registry.get_actions.map(&:name).join(", ")
        return [ nil, { tool_executed: false, error: "Unknown tool '#{invocation[:tool]}'. Available tools: #{available}" } ]
      end

      [ action, @environment.execute_action(action, invocation[:args]) ]
    end

    def run(user_input, memory: nil, max_iterations: 50)
      memory ||= Memory.new
      set_current_task(memory, user_input)

      max_iterations.times do |i|
        prompt = construct_prompt(@goals, memory, @action_registry)

        Rails.logger.info "[Agent] Iteration #{i + 1}: thinking..."
        response = prompt_llm_for_action(prompt)
        Rails.logger.info "[Agent] Decision: #{response.slice(:content, :tool_calls).inspect}"

        # Execute every tool call from this turn, then stop if a terminal tool succeeded
        # (a failed terminal call, e.g. invalid arguments, gives the model a chance to fix it)
        terminate = false
        results = @agent_language.parse_response(response).map do |invocation|
          action, result = execute_invocation(invocation)
          Rails.logger.info "[Agent] #{invocation[:tool]} -> #{result.inspect.truncate(500)}"
          terminate ||= action&.terminal? && result[:tool_executed]
          [ invocation[:tool], result ]
        end

        update_memory(memory, response, results)
        break if terminate
      end

      memory
    end
  end
end
