namespace :haussignal do
  desc "Resync email and unsub events for all existing leads"
  task resync_all: :environment do
    leads = Lead.all
    total = leads.count
    
    puts "🔄 Resyncing #{total} leads..."
    puts "=" * 60
    
    email_service = Lofty::Sync::EmailEventSyncService.new
    unsub_service = Lofty::Sync::UnsubEventSyncService.new
    
    success_count = 0
    failed = []
    
    leads.each_with_index do |lead, idx|
      lofty_lead_id = lead.lofty_lead_id
      
      print "[#{idx + 1}/#{total}] #{lofty_lead_id}... "
      
      begin
        # Sync emails (sent/opened)
        email_service.sync_for_lead(lofty_lead_id)
        
        # Sync unsubs
        unsub_service.sync_for_lead(lofty_lead_id)
        
        success_count += 1
        puts "✅"
      rescue => e
        failed << { id: lofty_lead_id, error: e.message }
        puts "❌ #{e.message}"
        Rails.logger.error "Failed to resync #{lofty_lead_id}: #{e.class} - #{e.message}"
      end
    end
    
    puts "=" * 60
    puts "✅ Resync complete!"
    puts "   Successful: #{success_count}/#{total}"
    puts "   Failed: #{failed.size}/#{total}"
    
    if failed.any?
      puts "\n⚠️ Failures:"
      failed.each do |f|
        puts "  - #{f[:id]}: #{f[:error]}"
      end
    end
  end
end
