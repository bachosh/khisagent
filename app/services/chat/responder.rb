module Chat
  # Answers one user message in a conversation. Uses the statement tools over the conversation's
  # analyzed statements, and the last messages as memory.
  class Responder
    MAX_ITERATIONS = 10
    HISTORY = 16

    def initialize(reply, llm_client: LLM.agent_client)
      @reply = reply
      @conversation = reply.conversation
      @llm_client = llm_client
      @language = Statements::RiskAgent::LANGUAGES.fetch(I18n.locale.to_s, "English")
    end

    def call
      statements = @conversation.statements.where(status: "analyzed").to_a
      registry = Agent::Tools::StatementTools.action_registry(statements, mode: :chat, language: @language)
      runner = Agent::Runner.new(
        goals: goals(statements), agent_language: Agent::Languages::FunctionCalling.new,
        action_registry: registry, llm_client: @llm_client,
        environment: Agent::ProgressEnvironment.new(on_action: ->(name) { @reply.add_tool_step!(name) unless name == "terminate" })
      )

      *history, question = previous_messages
      memory = Agent::Memory.new
      history.each { |m| memory.add_memory({ type: m.role, content: m.content }) }

      memory = runner.run(question.content, memory: memory, max_iterations: MAX_ITERATIONS)
      answer = memory.final_output
      answer.is_a?(String) && answer.present? ? answer : I18n.t("chat.no_answer")
    end

    private

    def previous_messages
      @conversation.messages.where(status: "done").where.not(content: "").where(id: ...@reply.id).last(HISTORY)
    end

    def goals(statements)
      [
        Agent::Goal.new(priority: 1, name: "Role", description: <<~TEXT.squish),
          You are KhisAgent, an assistant for risk managers at a credit company in Georgia. You analyze
          bank account statements of loan applicants. Answer in #{@language}, briefly and precisely, in Markdown.
          Use only #{@language} words (merchant names stay as in the statement).
        TEXT
        Agent::Goal.new(priority: 2, name: "Statements", description: statements_description(statements)),
        Agent::Goal.new(priority: 3, name: "Rules", description: <<~TEXT.squish)
          Use the tools for every number you give: never guess amounts, dates or counts. Mention operation ids
          when you cite operations. A single operation is not proof of insolvency; MCC 6051 alone does not
          prove crypto. If no statement is analyzed yet, say the risk manager can attach a statement with the
          paperclip button (CSV, Excel, PDF or a photo). End by calling terminate with your answer.
        TEXT
      ]
    end

    def statements_description(statements)
      return "No statement has been analyzed in this conversation yet." if statements.empty?

      lines = statements.map do |s|
        report = s.risk_report
        "- id #{s.id}: #{s.filename}, #{s.operations_count} operations, #{s.period_start}..#{s.period_end}, " \
          "#{s.display_currency}" + (report ? ", risk score #{report.risk_score} (#{report.risk_level}), #{report.recommendation}: #{report.summary.truncate(300)}" : "")
      end
      "Statements in this conversation:\n#{lines.join("\n")}"
    end
  end
end
