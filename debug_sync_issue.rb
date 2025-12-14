puts 'Debugging timeline sync processing issue...'
puts '=' * 60

begin
  # Check if the lead already has events
  lead = Lead.find_by(lofty_lead_id: '1142032162531031')
  if lead
    puts "BEFORE SYNC:"
    puts "  Lead exists: #{lead.id}"
    puts "  Events count: #{lead.events.count}"
    puts "  Timeline synced at: #{lead.timeline_synced_at}"
    puts "  Last event occurred at: #{lead.events.order(:occurred_at).last&.occurred_at}"
  end

  puts "\nRunning incremental sync to see filtering behavior..."
  service = Lofty::Sync::TimelineSyncService.new
  result = service.sync_for_lead('1142032162531031', incremental: true)

  puts "\nINCREMENTAL SYNC RESULT:"
  puts "  New events: #{result[:new] || 'nil'}"
  puts "  Skipped: #{result[:skipped] || 'nil'}"
  puts "  Already synced: #{result[:already_synced] || 'nil'}"
  puts "  Error: #{result[:error] || 'None'}"

  # Check after
  lead.reload
  puts "\nAFTER SYNC:"
  puts "  Events count: #{lead.events.count}"
  puts "  Timeline synced at: #{lead.timeline_synced_at}"

rescue => e
  puts "\nERROR:"
  puts "  #{e.message}"
  puts "  #{e.backtrace.first(3).join("\n  ")}"
end🚀 REAL-WORLD BATCH TEST - MONITORING MODE
