puts "Local - Will Sarver events:"
lead = Lead.find_by(lofty_lead_id: "1135935447791046")
puts "Events: #{lead.events.count}"
puts "Calls: #{lead.events.where(event_type: 'call').count}"
puts "Type codes: #{lead.events.group(:type_code).count.sort.to_h}"