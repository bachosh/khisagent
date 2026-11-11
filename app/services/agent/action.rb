# app/services/agent/action.rb
module Agent
  # Represents an executable action (the A in GAME)
  class Action
    attr_reader :name, :function, :description, :parameters, :terminal

    def initialize(name:, function:, description:, parameters:, terminal: false)
      @name = name
      @function = function
      @description = description
      @parameters = parameters
      @terminal = terminal
    end

    def execute(**args)
      function.call(**args)
    end

    def terminal?
      terminal
    end
  end
end
