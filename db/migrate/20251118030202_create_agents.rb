class CreateAgents < ActiveRecord::Migration[7.1]
  def change
    create_table :agents, id: :uuid do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :lofty_user_id

      t.timestamps
    end

    add_index :agents, :email, unique: true
    add_index :agents, :lofty_user_id, unique: true
  end
end
