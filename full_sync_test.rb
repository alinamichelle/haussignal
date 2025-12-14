puts 'COMPLETE SYNC TEST FOR BEN (1142032162531031)'
puts '=' * 60

lead = Lead.find_by(lofty_lead_id: '1142032162531031')

puts "BEFORE SYNC:"
puts "  Lead exists: #{!!lead}"
puts "  Events count: #{lead&.events&.count || 0}"
puts "  Timeline synced at: #{lead&.timeline_synced_at || 'NULL'}"

puts "\n🚀 STARTING FULL SYNC (incremental=false)..."
puts "-" * 40

service = Lofty::Sync::TimelineSyncService.new
result = service.sync_for_lead('1142032162531031', incremental: false)

puts "\n📊 SYNC RESULT:"
result.each do |key, value|
  puts "  #{key}: #{value}"
end

# Check what actually got saved
lead.reload
puts "\n✅ AFTER SYNC:"
puts "  Events count: #{lead.events.count}"
puts "  Timeline synced at: #{lead.timeline_synced_at}"

if lead.events.any?
  puts "\n📋 SAMPLE EVENTS (first 5):"
  lead.events.order(:occurred_at).limit(5).each_with_index do |event, i|
    puts "  #{i+1}. #{event.event_type} (#{event.occurred_at&.strftime('%Y-%m-%d')}) - #{event.raw_text&.truncate(50)}"
  end

  puts "\n📈 EVENT TYPE BREAKDOWN:"
  breakdown = lead.events.group(:event_type).count.sort_by { |k,v| -v }
  breakdown.each do |type, count|
    puts "  #{type}: #{count}"
  end
else
  puts "\n❌ NO EVENTS SAVED!"
end🚀 REAL-WORLD BATCH TEST - MONITORING MODE
