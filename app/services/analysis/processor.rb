module Statements
  # Full pipeline for one uploaded statement: import → metrics → risk agent → report → chat message.
  # Every step updates the statement, which broadcasts its card to the open chat.
  class Processor
    def self.call(statement)
      new(statement).call
    end

    def initialize(statement)
      @statement = statement
      @locale = statement.user.locale
    end

    def call
      I18n.with_locale(@locale) do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @statement.progress!(status: "extracting", note: I18n.t("statements.progress.reading"))
        Importer.new(@statement).call

        @statement.progress!(status: "analyzing", note: I18n.t("statements.progress.computing"))
        metrics = Metrics.new(@statement.reload).to_h
        attributes = RiskAgent.new(@statement, locale: @locale, on_action: method(:tool_progress)).run
        attributes ||= fallback_report(metrics)

        report = @statement.risk_report || @statement.build_risk_report
        report.update!(attributes.merge(metrics: metrics, language: @locale, model: LLM.config.model,
                                        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round))
        @statement.progress!(status: "analyzed", note: nil)
        post_summary(report)
      end
    rescue ImportError, OllamaChat::Error => e
      @statement.fail!(e.message)
    rescue StandardError => e
      Rails.logger.error "[Processor] statement #{@statement.id}: #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}"
      @statement.fail!(I18n.t("statements.errors.unexpected", locale: @locale))
    end

    private

    def tool_progress(tool_name)
      @statement.progress!(note: I18n.t("statements.tools.#{tool_name}", default: tool_name))
    end

    # The model did not submit a report within its iterations: keep the computed indicators
    def fallback_report(metrics)
      score = metrics.dig("indicator_score", "score")
      { risk_score: score, risk_level: RiskReport.level_for(score), recommendation: "manual_review",
        summary: I18n.t("reports.fallback_summary"), findings: [], strengths: [] }
    end

    def post_summary(report)
      text = I18n.t("reports.chat_summary", file: @statement.filename, score: report.risk_score,
                    level: I18n.t("risk_levels.#{report.risk_level}"),
                    recommendation: I18n.t("recommendations.#{report.recommendation}"), summary: report.summary)
      @statement.conversation.messages.create!(role: "assistant", content: text, status: "done")
      @statement.conversation.touch_activity!
    end
  end
end
