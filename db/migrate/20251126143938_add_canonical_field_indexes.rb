class AddCanonicalFieldIndexes < ActiveRecord::Migration[7.1]
  def change
    # Single column indexes for filtering
    add_index :events, :category, name: 'index_events_on_category_only'
    add_index :events, :channel, name: 'index_events_on_channel_only'
    add_index :events, :auto, name: 'index_events_on_auto_only'
    
    # Composite indexes for common query patterns
    add_index :events, [:lead_id, :category], name: 'index_events_on_lead_category'
    add_index :events, [:agent_id, :category], name: 'index_events_on_agent_category'
    add_index :events, [:lead_id, :auto], name: 'index_events_on_lead_auto'
    add_index :events, [:category, :occurred_at], name: 'index_events_on_category_occurred_at'
  end
end
