require "test_helper"

module Agent
  class RunnerTest < ActiveSupport::TestCase
    # Returns scripted assistant messages and records the prompts it was given
    class FakeLLMClient
      attr_reader :prompts

      def initialize(*responses)
        @responses = responses
        @prompts = []
      end

      def call(prompt)
        @prompts << prompt
        @responses.shift || { content: "out of script" }
      end
    end

    def tool_call(name, args)
      { function: { name: name, arguments: args } }
    end

    setup do
      ToolRegistry.clear
      Tools::SystemTools.register_all
      @weather_calls = []
      ToolRegistry.register(
        "get_weather",
        ->(city:) { @weather_calls << city; "#{city}: sunny" },
        description: "Get weather for a city",
        parameters: { type: "object", properties: { city: { type: "string" } }, required: [ "city" ] },
        tags: [ "weather" ]
      )
    end

    def run_agent(llm, task = "Weather in Tbilisi and Batumi?")
      Runner.new(
        goals: [ Goal.new(priority: 1, name: "Task", description: "Answer, then call terminate") ],
        agent_language: Languages::FunctionCalling.new,
        action_registry: ActionRegistry.from_tags([ "weather", "system" ]),
        llm_client: llm
      ).run(task, max_iterations: 5)
    end

    test "executes every tool call in one turn, then stops on terminate" do
      llm = FakeLLMClient.new(
        { content: "", tool_calls: [ tool_call("get_weather", { city: "Tbilisi" }), tool_call("get_weather", { city: "Batumi" }) ] },
        { content: "", tool_calls: [ tool_call("terminate", { message: "Both sunny" }) ] },
        { content: "should never be requested" }
      )

      memory = run_agent(llm)

      assert_equal [ "Tbilisi", "Batumi" ], @weather_calls
      assert_equal 2, llm.prompts.size
      assert_equal "Both sunny", memory.final_output
    end

    test "sends tool results back as role tool messages after the assistant tool calls" do
      llm = FakeLLMClient.new(
        { content: "", tool_calls: [ tool_call("get_weather", { city: "Tbilisi" }) ] },
        { content: "", tool_calls: [ tool_call("terminate", { message: "done" }) ] }
      )

      run_agent(llm)
      roles = llm.prompts.last.messages.map { |m| m[:role] }

      assert_equal %w[ system user assistant tool ], roles
      assert_equal "get_weather", llm.prompts.last.messages.last[:tool_name]
      assert_equal %w[ get_weather terminate ask_user ], llm.prompts.last.tools.map { |t| t.dig(:function, :name) }
    end

    test "accepts arguments as a JSON string" do
      llm = FakeLLMClient.new(
        { content: "", tool_calls: [ tool_call("get_weather", '{"city":"Kutaisi"}') ] },
        { content: "", tool_calls: [ tool_call("terminate", { message: "done" }) ] }
      )

      run_agent(llm)

      assert_equal [ "Kutaisi" ], @weather_calls
    end

    test "treats a plain text answer as the final answer" do
      memory = run_agent(FakeLLMClient.new({ content: "It is sunny." }))

      assert_equal "It is sunny.", memory.final_output
    end

    test "reports unknown tools and tool errors back to the model instead of crashing" do
      llm = FakeLLMClient.new(
        { content: "", tool_calls: [ tool_call("fly_to_moon", {}), tool_call("get_weather", {}) ] },
        { content: "", tool_calls: [ tool_call("terminate", { message: "recovered" }) ] }
      )

      memory = run_agent(llm)
      errors = memory.items.select { |m| m[:type] == "environment" }.first(2).map { |m| JSON.parse(m[:content])["error"] }

      assert_match "Unknown tool 'fly_to_moon'", errors.first
      assert_match "ArgumentError", errors.second
      assert_equal "recovered", memory.final_output
    end

    test "a failed terminal call does not stop the loop, so the model can fix it" do
      llm = FakeLLMClient.new(
        { content: "", tool_calls: [ tool_call("terminate", {}) ] },
        { content: "", tool_calls: [ tool_call("terminate", { message: "fixed" }) ] }
      )

      memory = run_agent(llm)

      assert_equal 2, llm.prompts.size
      assert_equal "fixed", memory.final_output
    end

    test "stops after max_iterations when the model never terminates" do
      looping = Array.new(10) { { content: "", tool_calls: [ tool_call("get_weather", { city: "Gori" }) ] } }
      run_agent(FakeLLMClient.new(*looping))

      assert_equal 5, @weather_calls.size
    end
  end
end
