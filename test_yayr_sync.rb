puts 'Testing sync for Yayr Cruz (1134222279220642)...'
puts '=' * 60

# Delete existing events for clean test
lead = Lead.find_by(lofty_lead_id: '1134222279220642')
if lead
  puts "Clearing #{lead.events.count} existing events for clean test..."
  lead.events.destroy_all
  lead.update_column(:timeline_synced_at, nil)
end

# Run sync
service = Lofty::Sync::TimelineSyncService.new
result = service.sync_for_lead('1134222279220642', incremental: false)

puts ''
puts 'SYNC RESULT:'
puts "  New events: #{result.except(:skipped, :errors).values.sum}"
puts "  Skipped: #{result[:skipped] || 0}"
puts "  Errors: #{result[:errors] || 0}"
puts ''

# Check what was saved
lead.reload
puts 'DATABASE CHECK:'
puts "  Total events: #{lead.events.count}"
puts "  Timeline synced: #{lead.timeline_synced_at ? 'YES' : 'NO'}"
puts ''

if lead.events.any?
  puts 'EVENT TYPE DISTRIBUTION:'
  lead.events.group(:event_type).count.sort_by{|k,v| -v}.each { |type, count| puts "  #{type}: #{count}" }
  puts ''
  
  puts 'CANONICAL TYPE SAMPLES (first 10):'
  lead.events.limit(10).each do |e|
    canonical = e.metadata['canonical_event_type'] rescue nil
    puts "  [#{e.type_code}] #{e.event_type} -> canonical: #{canonical || 'none'}"
  end
end
