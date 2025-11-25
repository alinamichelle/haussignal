class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false, index: { unique: true }
      t.string :password_digest, null: false
      t.integer :role, null: false, default: 2
      t.string :name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
