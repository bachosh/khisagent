module Analysis
  class Statement < ApplicationRecord
    STATUSES = %w[ queued extracting analyzing analyzed failed ].freeze
    PROCESSING = %w[ queued extracting analyzing ].freeze
    MAX_FILE_SIZE = 25.megabytes

    KINDS = {
      "csv" => %w[ text/csv text/plain application/csv application/vnd.ms-excel ],
      "xlsx" => %w[ application/vnd.openxmlformats-officedocument.spreadsheetml.sheet ],
      "xls" => %w[ application/vnd.ms-excel application/x-ole-storage ],
      "pdf" => %w[ application/pdf ],
      "image" => %w[ image/png image/jpeg image/webp ]
    }.freeze
    EXTENSIONS = {
      ".csv" => "csv", ".txt" => "csv", ".xlsx" => "xlsx", ".xls" => "xls", ".pdf" => "pdf",
      ".png" => "image", ".jpg" => "image", ".jpeg" => "image", ".webp" => "image"
    }.freeze

    belongs_to :user
    belongs_to :conversation, class_name: "Chat::Conversation"
    belongs_to :message, class_name: "Chat::Message", optional: true
    has_one_attached :file
    has_many :operations, -> { order(:position) }, dependent: :delete_all
    has_one :risk_report, dependent: :destroy
    # The assistant's "analyzed" message in the chat (holds the client's name and findings)
    has_many :summary_messages, class_name: "Chat::Message", foreign_key: :summarized_statement_id,
                                inverse_of: :summarized_statement, dependent: :destroy

    validates :filename, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :file_kind, inclusion: { in: KINDS.keys, message: :unsupported }
    validate :file_size_within_limit

    after_update_commit :broadcast_changes
    after_destroy :destroy_empty_upload_message
    after_destroy_commit :broadcast_removal

    STATUSES.each { |status| define_method("#{status}?") { self.status == status } }

    def self.kind_for(filename)
      EXTENSIONS[File.extname(filename.to_s).downcase]
    end

    def self.accepted_extensions
      EXTENSIONS.keys.join(",")
    end

    def processing?
      PROCESSING.include?(status)
    end

    # A processing statement that has not changed for a while lost its job (e.g. the server restarted)
    STALL_AFTER = 15.minutes

    def stalled?
      processing? && updated_at < STALL_AFTER.ago
    end

    def progress!(status: self.status, note: nil)
      update!(status: status, progress: note)
    end

    def fail!(error)
      update!(status: "failed", error: error.to_s.truncate(1000), progress: nil)
    end

    def total_in
      operations.where("amount > 0").sum(:amount)
    end

    def total_out
      -operations.where("amount < 0").sum(:amount)
    end

    def period_label
      return if period_start.blank?

      [ period_start, period_end ].compact.map { |d| I18n.l(d, format: :short_date) }.uniq.join(" – ")
    end

    def display_currency
      currency.presence || "GEL"
    end

    private

    # The user message only carried this file: nothing left to show
    def destroy_empty_upload_message
      return unless message && !message.destroyed?

      message.destroy! if message.content.blank? && message.statements.where.not(id: id).none?
    end

    def broadcast_removal
      broadcast_remove_to conversation
      return unless Chat::Conversation.exists?(conversation_id) # the whole chat is being deleted

      broadcast_replace_to conversation, target: "conversation_insights", partial: "chat/conversations/insights",
                                         locals: { conversation: conversation }
    end

    def file_size_within_limit
      errors.add(:file, :too_large, max: MAX_FILE_SIZE / 1.megabyte) if file.attached? && file.blob.byte_size > MAX_FILE_SIZE
    end

    def broadcast_changes
      broadcast_replace_to conversation, partial: "analysis/statements/statement", locals: { statement: self }
      broadcast_replace_to conversation, target: "conversation_insights", partial: "chat/conversations/insights",
                                         locals: { conversation: conversation }
    end
  end
end
