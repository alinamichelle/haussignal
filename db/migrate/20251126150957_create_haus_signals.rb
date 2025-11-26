class CreateHausSignals < ActiveRecord::Migration[7.1]
  def change
    create_table :haus_signals, id: :uuid do |t|
      t.references :lead, null: false, foreign_key: true, type: :uuid
      t.references :agent, null: true, foreign_key: { to_table: :agents }, type: :uuid
      t.string :signal_type, null: false
      t.string :severity, null: false, default: 'medium'
      t.jsonb :metadata, null: false, default: {}
      t.datetime :first_detected_at, null: false
      t.datetime :last_seen_at, null: false
      t.string :status, null: false, default: 'active'

      t.timestamps
    end

    add_index :haus_signals, [:agent_id, :signal_type]
    add_index :haus_signals, [:lead_id, :signal_type], unique: true
    add_index :haus_signals, :status
    add_index :haus_signals, :severity
  end
end
