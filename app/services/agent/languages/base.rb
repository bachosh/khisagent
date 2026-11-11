# app/services/agent/languages/base.rb
module Agent
  module Languages
    # Base class for agent languages (prompt formatting strategies)
    class Base
      def construct_prompt(actions:, environment:, goals:, memory:)
        raise NotImplementedError, "Subclasses must implement construct_prompt"
      end

      # Must return an array of invocations: [{ tool: "name", args: {...} }, ...]
      def parse_response(response)
        raise NotImplementedError, "Subclasses must implement parse_response"
      end
    end
  end
end
