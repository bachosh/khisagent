module Chat
  # A user's message with optional files: saves the message, turns each file into a Statement queued
  # for analysis, and queues the assistant's reply when there is a question.
  class Submission
    MAX_FILES = 5

    attr_reader :conversation, :errors

    def initialize(user:, conversation: nil, content: nil, files: [])
      @user = user
      @conversation = conversation
      @content = content.to_s.strip
      @files = Array(files).compact_blank.first(MAX_FILES)
      @errors = []
    end

    def call
      return fail_with(I18n.t("chat.empty_message")) if @content.blank? && @files.empty?

      unsupported = @files.reject { |f| Statement.kind_for(f.original_filename) }
      return fail_with(I18n.t("statements.errors.unsupported_files", names: unsupported.map(&:original_filename).join(", "))) if unsupported.any?

      ActiveRecord::Base.transaction do
        @conversation ||= @user.conversations.create!
        message = @conversation.messages.create!(role: "user", content: @content)
        @statements = @files.map { |file| create_statement(file, message) }
        @conversation.title_from!(@content.presence || @statements.first&.filename)
        @reply = @conversation.messages.create!(role: "assistant", status: "pending") if @content.present?
        @conversation.touch_activity!
      end

      @statements.each { |s| StatementProcessingJob.perform_later(s) }
      ChatReplyJob.perform_later(@reply) if @reply
      true
    rescue ActiveRecord::RecordInvalid => e
      fail_with(e.record.errors.full_messages.to_sentence)
    end

    private

    def create_statement(file, message)
      @user.statements.create!(conversation: @conversation, message: message, filename: file.original_filename.to_s.truncate(200),
                               file_kind: Statement.kind_for(file.original_filename), file: file)
    end

    def fail_with(error)
      @errors << error
      false
    end
  end
end
