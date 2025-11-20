namespace :haussignal do
  desc "Test sync for single lead with detailed logging"
  task :test_single_lead, [:lead_id] => :environment do |t, args|
    lead_id = args[:lead_id] || "1142886436094613"
    
    puts "🧪 Testing sync for lead #{lead_id}"
    puts "="  * 50
    
    # Clean slate
    lead = Lead.find_or_create_by(lofty_lead_id: lead_id) { |l| l.org_id = "realty-haus" }
    Event.where(lead: lead).delete_all
    puts "✅ Cleared all events"
    
    # Sync emails
    puts "\n📧 Syncing emails..."
    email_sync = Lofty::Sync::EmailEventSyncService.new
    email_stats = email_sync.sync_for_lead(lead_id)
    puts "   Sent: #{email_stats[:email_sent]}"
    puts "   Opened: #{email_stats[:email_opened]}"
    puts "   Skipped: #{email_stats[:skipped]}"
    
    # Sync unsubs
    puts "\n🚫 Syncing unsubs..."
    unsub_sync = Lofty::Sync::UnsubEventSyncService.new
    unsub_stats = unsub_sync.sync_for_lead(lead_id)
    puts "   New: #{unsub_stats[:new]}"
    puts "   Missing email: #{unsub_stats[:missing_email]}"
    puts "   Missing subject: #{unsub_stats[:missing_subject]}"
    
    # Show what we got
    puts "\n📊 Final Results:"
    puts "   Total events: #{Event.where(lead: lead).count}"
    puts "   Event types: #{Event.where(lead: lead).pluck(:event_type).uniq.join(", ")}"
    
    # Show first unsub
    unsub = Event.where(lead: lead, event_type: "unsub").first
    if unsub
      puts "\n🔍 First Unsub Event:"
      puts "   Date: #{unsub.occurred_at}"
      puts "   Category: #{unsub.metadata["unsubCategory"]}"
      trigger = unsub.metadata["triggerEmail"]
      if trigger
        puts "   Trigger Email Type: #{trigger["emailType"]}"
        puts "   Trigger Email Subject: #{trigger["emailSubject"]&.truncate(60)}"
        puts "   Open Status: #{trigger["openStatus"]}"
      else
        puts "   ⚠️  NO TRIGGER EMAIL DATA"
      end
    end
  end
end
