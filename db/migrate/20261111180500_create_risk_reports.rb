class CreateRiskReports < ActiveRecord::Migration[8.1]
  def change
    create_table :risk_reports do |t|
      t.references :statement, null: false, foreign_key: true, index: { unique: true }
      t.integer :risk_score, null: false
      t.string :risk_level, null: false               # low | medium | high | critical
      t.string :recommendation, null: false           # approve | approve_with_conditions | manual_review | decline
      t.text :summary, null: false
      t.json :findings, null: false, default: []
      t.json :strengths, null: false, default: []
      t.json :metrics, null: false, default: {}
      t.decimal :estimated_monthly_income, precision: 15, scale: 2
      t.decimal :estimated_monthly_debt_payments, precision: 15, scale: 2
      t.string :language
      t.string :model
      t.integer :duration_ms
      t.timestamps
    end
  end
end
