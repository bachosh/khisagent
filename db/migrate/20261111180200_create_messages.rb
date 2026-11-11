class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false                      # user | assistant
      t.text :content, null: false, default: ""
      t.string :status, null: false, default: "done"   # pending | done | failed
      t.string :progress                               # what the agent is doing right now
      t.json :tool_steps, null: false, default: []     # tools the agent used for this reply
      t.integer :duration_ms
      t.timestamps
    end
  end
end
