class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, -> { order(:id) }, dependent: :destroy
  has_many :statements, -> { order(:id) }, dependent: :destroy

  before_validation { self.last_activity_at ||= Time.current }

  scope :recent, -> { order(last_activity_at: :desc) }

  def display_title
    title.presence || I18n.t("conversations.untitled")
  end

  def touch_activity!
    update_columns(last_activity_at: Time.current)
  end

  # Names the chat after its first file or question, unless the user renamed it
  def title_from!(text)
    update!(title: text.to_s.squish.truncate(60)) if title.blank? && text.present?
  end

  def busy?
    messages.any?(&:pending?) || statements.any?(&:processing?)
  end
end
