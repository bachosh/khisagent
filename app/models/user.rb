class User < ApplicationRecord
  LOCALES = %w[ ka en ].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :statements, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, :company, with: ->(value) { value.strip }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :locale, inclusion: { in: LOCALES }

  def initials
    name.split.first(2).map { |part| part[0] }.join.upcase.presence || email_address[0].upcase
  end

  def first_name
    name.split.first || name
  end
end
