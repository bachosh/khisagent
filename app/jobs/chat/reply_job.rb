module Chat
  # Writes the assistant's reply into a pending message. Waits while files of the
  # conversation are still being analyzed, so the answer can use them.
  class ReplyJob < ApplicationJob
    queue_as :default
    discard_on ActiveJob::DeserializationError
    WAIT = 4.seconds
    MAX_WAIT = 20.minutes

    def perform(reply, enqueued_at = Time.current.to_i)
      return unless reply.pending? && Chat::Message.exists?(reply.id)

      I18n.with_locale(reply.conversation.user.locale) do
        if reply.conversation.statements.any?(&:processing?) && Time.current.to_i - enqueued_at < MAX_WAIT
          reply.update!(progress: "waiting_for_files") unless reply.progress == "waiting_for_files"
          return self.class.set(wait: WAIT).perform_later(reply, enqueued_at)
        end

        reply = move_to_end(reply)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        answer = Chat::Responder.new(reply).call
        reply.update!(content: answer, status: "done", progress: nil,
                      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      rescue OllamaChat::Error => e
        reply.update!(content: I18n.t("chat.llm_unavailable", error: e.message), status: "failed", progress: nil)
      rescue StandardError => e
        Rails.logger.error "[Chat::ReplyJob] #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}"
        reply.update!(content: I18n.t("chat.failed"), status: "failed", progress: nil)
      end
    end

    private

    # While the reply waited for the files, the analysis posted its summary below it. Recreate the
    # placeholder at the end so the answer comes after the summary it builds on.
    def move_to_end(reply)
      return reply if reply.conversation.messages.where("id > ?", reply.id).none?

      reply.destroy!
      reply.conversation.messages.create!(role: "assistant", status: "pending")
    end
  end
end
