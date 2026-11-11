class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string, null: false, default: ""
    add_column :users, :company, :string
    add_column :users, :locale, :string, null: false, default: "ka"
  end
end
