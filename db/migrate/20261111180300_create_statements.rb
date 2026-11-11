class CreateStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :statements do |t|
      t.references :user, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :message, foreign_key: true          # the chat message the file was uploaded with
      t.string :filename, null: false
      t.string :file_kind, null: false                     # csv | xlsx | xls | pdf | image
      t.string :status, null: false, default: "queued"     # queued | extracting | analyzing | analyzed | failed
      t.string :progress
      t.text :error
      t.string :extraction_method                          # table | pdf_text | vision
      t.json :column_mapping
      t.string :bank_name
      t.string :account_holder
      t.string :account_number
      t.string :currency
      t.date :period_start
      t.date :period_end
      t.decimal :opening_balance, precision: 15, scale: 2
      t.decimal :closing_balance, precision: 15, scale: 2
      t.integer :operations_count, null: false, default: 0
      t.timestamps
    end
  end
end
