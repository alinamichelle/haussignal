puts 'Testing TimelineSyncService with modified scraper'
puts '=' * 60

begin
  service = Lofty::Sync::TimelineSyncService.new

  # Test the sync service with our sample lead
  result = service.sync_for_lead('1142032162531031', incremental: false)

  puts 'TIMELINE SYNC RESULT:'
  puts '  New events: ' + result[:new].to_s
  puts '  Skipped: ' + result[:skipped].to_s
  puts '  Error: ' + (result[:error] || 'None').to_s
  puts '  Message: ' + (result[:message] || 'None').to_s

  # Check the lead status
  lead = Lead.find_by(lofty_lead_id: '1142032162531031')
  if lead
    puts ''
    puts 'LEAD STATUS:'
    puts '  Timeline synced at: ' + (lead.timeline_synced_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Not synced')
    puts '  Events count: ' + lead.events.count.to_s
  end

rescue => e
  puts 'ERROR:'
  puts '  ' + e.message
  puts '  ' + e.backtrace.first(3).join("\n  ")
end

puts "\n" + "=" * 60
puts "Timeline sync test completed!"🚀 REAL-WORLD BATCH TEST - MONITORING MODE
