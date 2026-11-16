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

    after_create_commit :broadcast_created
    after_update_commit -> { broadcast_replace_to conversation, partial: "chat/messages/message" }
    after_destroy_commit -> { broadcast_remove_to conversation }

    ROLES.each { |role| define_method("#{role}?") { self.role == role } }
    STATUSES.each { |status| define_method("#{status}?") { self.status == status } }

    # Display order: by creation, except that a statement's "analyzed" summary sits right after the message
    # that uploaded the file, however late the analysis finishes (see Chat::Conversation#displayed_messages)
    def display_key
      anchor = summarized_statement&.message_id
      anchor ? [ anchor, 1, id ] : [ id, 0, id ]
    end

    def add_tool_step!(tool_name)
      update!(tool_steps: tool_steps + [ tool_name ], progress: tool_name)
    end

    private

    # Insert the new message where it belongs in the display order (usually the end)
    def broadcast_created
      ordered = conversation.displayed_messages
      index = ordered.index { |m| m.id == id }
      rendering = { partial: "chat/messages/message", locals: { message: self } }

      if index.nil? || index == ordered.size - 1
        broadcast_append_to conversation, target: "messages", **rendering
      elsif index.zero?
        broadcast_prepend_to conversation, target: "messages", **rendering
      else
        broadcast_after_to conversation, target: ActionView::RecordIdentifier.dom_id(ordered[index - 1]), **rendering
      end
    end
  end
end
