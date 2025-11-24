class AddSyncSlotToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :sync_slot, :integer
  end
end
