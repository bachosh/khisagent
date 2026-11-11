class RiskReport < ApplicationRecord
  LEVELS = %w[ low medium high critical ].freeze
  RECOMMENDATIONS = %w[ approve approve_with_conditions manual_review decline ].freeze
  SEVERITIES = %w[ info low medium high critical ].freeze

  belongs_to :statement

  validates :risk_score, numericality: { only_integer: true, in: 0..100 }
  validates :risk_level, inclusion: { in: LEVELS }
  validates :recommendation, inclusion: { in: RECOMMENDATIONS }
  validates :summary, presence: true

  def self.level_for(score)
    case score
    when 0...30 then "low"
    when 30...55 then "medium"
    when 55...80 then "high"
    else "critical"
    end
  end

  def sorted_findings
    findings.sort_by { |f| -SEVERITIES.index(f["severity"]).to_i }
  end
end
