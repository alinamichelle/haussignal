class AddCsvNotesToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :csv_notes, :text
  end
end
