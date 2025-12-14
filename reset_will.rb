lead = Lead.find_by(lofty_lead_id: "1135935447791046")
puts "Will Sarver - Current: #{lead.timeline_synced_at}"  
lead.update!(timeline_synced_at: nil)
puts "Reset to nil for full resync"
