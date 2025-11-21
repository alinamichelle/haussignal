class AddTimelineSyncedAtToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :timeline_synced_at, :datetime
    add_index :leads, :timeline_synced_at
  end
end
