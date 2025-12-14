puts "=== ACTIVITY PERFORMERS (NOT LEAD ASSIGNMENTS) ==="

# Analyze who actually performed manual activities
manual_events = Event.where(event_type: ['call', 'note', 'task', 'manual_unsub'])

performer_counts = {}
lead_owner_vs_performer = {}

manual_events.find_each(batch_size: 1000) do |event|
  performer = 'Unknown'

  if event.metadata && event.metadata['raw_json']
    begin
      raw_data = JSON.parse(event.metadata['raw_json'])
      if raw_data['fromFirstName'] && raw_data['fromLastName']
        performer = "#{raw_data['fromFirstName']} #{raw_data['fromLastName']}"
      end
    rescue
      performer = 'Unknown'
    end
  end

  # Count by actual performer
  performer_counts[performer] ||= 0
  performer_counts[performer] += 1

  # Track lead owner vs performer
  lead = event.lead
  lead_owner = lead&.agent&.name || 'No Agent'

  key = "#{lead_owner} -> #{performer}"
  lead_owner_vs_performer[key] ||= 0
  lead_owner_vs_performer[key] += 1
end

puts "\n=== TOP ACTIVITY PERFORMERS (ACTUAL PEOPLE DOING WORK) ==="
performer_counts.sort_by { |k,v| -v }.first(15).each do |performer, count|
  percentage = (count.to_f / manual_events.count * 100).round(1)
  puts "#{performer.ljust(25)} #{count.to_s.rjust(8)} (#{percentage}%)"
end

puts "\n=== TOP CROSS-AGENT WORK (Agent A doing work on Agent B's leads) ==="
cross_work = lead_owner_vs_performer.reject { |k,v| k.include?(' -> Unknown') || k.include?('-> No Agent') }
                                   .reject { |k,v| k.split(' -> ')[0] == k.split(' -> ')[1] }
                                   .sort_by { |k,v| -v }
                                   .first(20)

cross_work.each do |relationship, count|
  parts = relationship.split(' -> ')
  lead_owner = parts[0]
  performer = parts[1]
  puts "#{performer.ljust(20)} did #{count.to_s.rjust(5)} activities on #{lead_owner}'s leads"
end

puts "\n=== MATT CORDOVA'S WORK BREAKDOWN ==="
matt_work = lead_owner_vs_performer.select { |k,v| k.include?(' -> Matt Cordova') }
                                  .sort_by { |k,v| -v }

matt_work.each do |relationship, count|
  lead_owner = relationship.split(' -> ')[0]
  puts "Matt did #{count.to_s.rjust(5)} activities on #{lead_owner}'s leads"
end

puts "\n=== ANTHONY GIBSON'S WORK BREAKDOWN ==="
anthony_work = lead_owner_vs_performer.select { |k,v| k.include?(' -> Anthony Gibson') }
                                     .sort_by { |k,v| -v }

anthony_work.each do |relationship, count|
  lead_owner = relationship.split(' -> ')[0]
  puts "Anthony did #{count.to_s.rjust(5)} activities on #{lead_owner}'s leads"
end