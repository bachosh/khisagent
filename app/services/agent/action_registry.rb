# app/services/agent/action_registry.rb
module Agent
  # The actions one agent is allowed to use (a subset of ToolRegistry)
  class ActionRegistry
    attr_reader :actions

    # Build a registry from every ToolRegistry tool that has any of the tags
    def self.from_tags(tags)
      registry = new
      ToolRegistry.get_by_tags(tags).each do |metadata|
        registry.register(Action.new(**metadata.slice(:name, :function, :description, :parameters, :terminal)))
      end
      registry
    end

    def initialize
      @actions = {}
    end

    def register(action)
      @actions[action.name.to_s] = action
    end

    def get_action(name)
      @actions[name.to_s]
    end

    def get_actions
      @actions.values
    end
  end
end
