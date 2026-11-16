class Message < ApplicationRecord
  ROLES = %w[ user assistant ].freeze
  STATUSES = %w[ pending done failed ].freeze

  belongs_to :conversation
  has_many :statements, -> { order(:id) }, dependent: :nullify # files uploaded with this message

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :content, length: { maximum: 20_000 }

  after_create_commit -> { broadcast_append_to conversation, target: "messages", partial: "messages/message" }
  after_update_commit -> { broadcast_replace_to conversation, partial: "messages/message" }

  ROLES.each { |role| define_method("#{role}?") { self.role == role } }
  STATUSES.each { |status| define_method("#{status}?") { self.status == status } }

  def add_tool_step!(tool_name)
    update!(tool_steps: tool_steps + [ tool_name ], progress: tool_name)
  end
end
