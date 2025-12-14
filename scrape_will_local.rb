puts "🔍 Scraping Will Sarver locally..."

# Reset Will Sarver for fresh scrape
lead = Lead.find_by(lofty_lead_id: "1135935447791046")
puts "Before scrape - Events: #{lead.events.count}"

# Clear existing events to see what fresh scrape finds
lead.events.destroy_all
lead.update!(timeline_synced_at: nil)

puts "Running fresh scrape..."
service = Lofty::Sync::TimelineSyncService.new
result = service.sync_for_lead("1135935447791046")

# Check results
lead.reload
puts "\n📊 SCRAPE RESULTS:"
puts "Total events found: #{lead.events.count}"
puts "Call events: #{lead.events.where(event_type: 'call').count}"
puts "\nAll type codes found:"
lead.events.group(:type_code).count.sort.each { |tc, count|
  event_type = Lofty::TimelineParser::TYPE_CODE_MAPPINGS[tc] || :unmapped
  puts "Type #{tc}: #{count} events (maps to: #{event_type})"
}

puts "\nCall events details:"
lead.events.where(event_type: 'call').each do |call|
  puts "- Type #{call.type_code}: #{call.occurred_at} - #{call.raw_text[0..60]}..."
end

puts "\nUnmapped type codes (defaulting to :other):"
unmapped_codes = lead.events.select { |e| !Lofty::TimelineParser::TYPE_CODE_MAPPINGS.key?(e.type_code) }
unmapped_codes.group_by(&:type_code).each do |tc, events|
  puts "Type #{tc}: #{events.count} events"
  puts "  Sample: #{events.first.raw_text[0..80]}..." if events.first.raw_text.present?
end