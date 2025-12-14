puts "Running full sync for Will Sarver..."
service = Lofty::Sync::TimelineSyncService.new
result = service.sync_for_lead("1135935447791046")
puts "Sync complete!"

lead = Lead.find_by(lofty_lead_id: "1135935447791046")
puts "Total events: #{lead.events.count}"
call_events = lead.events.where(event_type: "call")
puts "Call events: #{call_events.count}"

if call_events.any?
  puts "Recent call events:"
  call_events.order(occurred_at: :desc).limit(5).each do |e|
    puts "- #{e.occurred_at}: #{e.raw_text[0..80]}..."
  end
else
  puts "No call events found - checking type codes..."
  lead.events.group(:type_code).count.each do |tc, count|
    puts "Type #{tc}: #{count} events"
  end
end