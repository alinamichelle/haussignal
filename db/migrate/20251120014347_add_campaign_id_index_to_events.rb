class AddCampaignIdIndexToEvents < ActiveRecord::Migration[7.1]
  def change
    # Add index on campaign_id stored in metadata JSONB column
    # This speeds up queries filtering by metadata->>'campaign_id'
    # NOTE: Will revisit indexing strategy as data volume grows
    add_index :events, "(metadata->>'campaign_id')", name: 'index_events_on_campaign_id'
  end
end
