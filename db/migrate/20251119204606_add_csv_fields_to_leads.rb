class AddCsvFieldsToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :lead_type, :string
    add_column :leads, :notes, :text
  end
end
