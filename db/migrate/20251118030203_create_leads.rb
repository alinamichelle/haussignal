class CreateLeads < ActiveRecord::Migration[7.1]
  def change
    create_table :leads, id: :uuid do |t|
      t.string  :org_id, null: false, default: 'realty-haus'
      t.string  :lofty_lead_id, null: false

      t.string  :full_name
      t.string  :first_name
      t.string  :last_name
      t.string  :email
      t.string  :phone
      t.string  :status
      t.string  :source
      t.text    :tags, array: true, default: []

      t.references :agent, type: :uuid, foreign_key: true

      t.datetime :created_at_lofty
      t.datetime :updated_at_lofty
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :leads, :lofty_lead_id, unique: true
  end
end
