class AddDetailsFieldsToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :pipeline, :string
    add_column :leads, :segment, :string
    add_column :leads, :reg_date, :datetime
  end
end
