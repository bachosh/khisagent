class CreateOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :operations do |t|
      t.references :statement, null: false, foreign_key: true
      t.integer :position, null: false
      t.date :booked_on
      t.text :description, null: false, default: ""
      t.string :counterparty
      t.decimal :amount, precision: 15, scale: 2, null: false  # signed: + incoming, - outgoing
      t.string :currency
      t.decimal :balance, precision: 15, scale: 2
      t.string :mcc                                    # Merchant Category Code (4 digits), when the statement has it
      t.string :transaction_code                       # ISO 8583 processing code (first 2 digits), when present
      t.string :category, null: false, default: "other"
      t.string :category_group, null: false, default: "unknown" # stage I class, see config/bank_codes.yml
    end
    add_index :operations, [ :statement_id, :position ]
    add_index :operations, [ :statement_id, :category ]
    add_index :operations, [ :statement_id, :category_group ]
    add_index :operations, [ :statement_id, :booked_on ]
  end
end
