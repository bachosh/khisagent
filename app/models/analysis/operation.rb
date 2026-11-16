# One line of a bank statement. amount is signed: positive = incoming, negative = outgoing.
class Operation < ApplicationRecord
  belongs_to :statement

  validates :category, inclusion: { in: ->(_) { Statements::BankCodes.categories } }
  validates :category_group, inclusion: { in: ->(_) { Statements::BankCodes.groups } }

  scope :incoming, -> { where("amount > 0") }
  scope :outgoing, -> { where("amount < 0") }

  def risky?
    Statements::BankCodes.risky?(category)
  end

  def incoming?
    amount.positive?
  end

  def to_tool_hash
    {
      id: position, date: booked_on&.iso8601, amount: amount.to_f, balance: balance&.to_f,
      category: category, group: category_group, mcc: mcc, counterparty: counterparty,
      description: description.truncate(200)
    }.compact
  end
end
