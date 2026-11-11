class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.datetime :last_activity_at, null: false
      t.timestamps
    end
    add_index :conversations, [ :user_id, :last_activity_at ]
  end
end
