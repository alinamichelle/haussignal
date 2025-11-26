class AddCanonicalFieldsToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :category,             :string
    add_column :events, :channel,              :string
    # source column already exists, skipping
    add_column :events, :auto,                 :boolean, default: false, null: false
    add_column :events, :direction,            :string
    add_column :events, :marketing_kind,       :string
    add_column :events, :communication_kind,   :string
    add_column :events, :task_origin,          :string
    add_column :events, :smart_plan_step_kind, :string
    add_column :events, :profile_change_type,  :string

    add_index :events, [:category, :channel]
    add_index :events, :auto
    add_index :events, :category
    add_index :events, :channel
  end
end
