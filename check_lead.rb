lead = Lead.find_by(lofty_lead_id: "1136293898032694")
if lead
  puts "Lead: #{lead.full_name}"
  puts "Events: #{lead.events.count}"
  call_events = lead.events.where(event_type: "call")
  puts "Call events: #{call_events.count}"
  puts "Type codes found:"
  lead.events.group(:type_code).count.sort.each { |tc, count| puts "Type #{tc}: #{count} events" }
else
  puts "Lead not found"
end