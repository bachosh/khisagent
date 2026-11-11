module Agent
  # Environment that reports each tool call (e.g. to show "reading monthly cash flow..." in the UI)
  class ProgressEnvironment < Environment
    def initialize(on_action:)
      @on_action = on_action
    end

    def execute_action(action, args)
      @on_action.call(action.name)
      super
    end
  end
end
