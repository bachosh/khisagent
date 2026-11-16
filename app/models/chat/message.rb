module Chat
  class Message < ApplicationRecord
    ROLES = %w[ user assistant ].freeze
    STATUSES = %w[ pending done failed ].freeze

    belongs_to :conversation
    belongs_to :summarized_statement, class_name: "Analysis::Statement", optional: true, inverse_of: :summary_messages
    has_many :statements, -> { order(:id) }, class_name: "Analysis::Statement", dependent: :nullify # files uploaded with this message

    validates :role, inclusion: { in: ROLES }
    validates :status, inclusion: { in: STATUSES }
    validates :content, length: { maximum: 20_000 }

    after_create_commit -> { broadcast_append_to conversation, target: "messages", partial: "chat/messages/message", locals: { message: self } }
    after_update_commit -> { broadcast_replace_to conversation, partial: "chat/messages/message" }
    after_destroy_commit -> { broadcast_remove_to conversation }

    ROLES.each { |role| define_method("#{role}?") { self.role == role } }
    STATUSES.each { |status| define_method("#{status}?") { self.status == status } }

    def add_tool_step!(tool_name)
      update!(tool_steps: tool_steps + [ tool_name ], progress: tool_name)
    end
  end
end
