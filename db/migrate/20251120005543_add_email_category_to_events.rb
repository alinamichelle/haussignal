class AddEmailCategoryToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :email_category, :string
  end
end
