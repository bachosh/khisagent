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
  belongs_to :conversation
  belongs_to :message, optional: true
  has_one_attached :file
  has_many :operations, -> { order(:position) }, dependent: :delete_all
  has_one :risk_report, dependent: :destroy

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :file_kind, inclusion: { in: KINDS.keys, message: :unsupported }
  validate :file_size_within_limit

  after_update_commit :broadcast_changes

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

  def file_size_within_limit
    errors.add(:file, :too_large, max: MAX_FILE_SIZE / 1.megabyte) if file.attached? && file.blob.byte_size > MAX_FILE_SIZE
  end

  def broadcast_changes
    broadcast_replace_to conversation, partial: "statements/statement", locals: { statement: self }
    broadcast_replace_to conversation, target: "conversation_insights", partial: "conversations/insights",
                                       locals: { conversation: conversation }
  end
end
