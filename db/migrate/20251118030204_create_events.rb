class CreateEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :events, id: :uuid do |t|
      t.string  :org_id, null: false, default: 'realty-haus'
      t.string  :source, null: false, default: 'lofty'

      t.string  :lofty_timeline_id, null: false
      t.integer :type_code, null: false
      t.string  :event_type, null: false

      t.datetime :occurred_at, null: false
      t.datetime :edited_at

      t.text    :raw_text
      t.jsonb   :metadata, default: {}

      t.references :lead,  type: :uuid, null: false, foreign_key: true
      t.references :agent, type: :uuid, foreign_key: true

      t.timestamps
    end

    add_index :events, :lofty_timeline_id, unique: true
    add_index :events, :event_type
    add_index :events, :occurred_at
  end
end
