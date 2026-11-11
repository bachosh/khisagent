# app/services/agent/goal.rb
module Agent
  # Represents an agent's goal (the G in GAME)
  class Goal
    attr_reader :priority, :name, :description

    def initialize(priority:, name:, description:)
      @priority = priority
      @name = name
      @description = description
    end
  end
end
