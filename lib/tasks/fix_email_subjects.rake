namespace :haussignal do
  desc "Fix emailSubject metadata for existing email_sent events"
  task fix_email_subjects: :environment do
    puts "🔧 Fixing email subjects for email_sent events..."
    
    # Find all email_sent events where the subject is actually the header
    events = Event.where(event_type: 'email_sent')
                  .where("metadata->>'emailSubject' LIKE '%[Manual E-Mail]%' OR metadata->>'emailSubject' LIKE '%[Auto E-Mail]%'")
    
    total = events.count
    puts "Found #{total} events with header as subject"
    
    return if total == 0
    
    fixed = 0
    failed = 0
    
    events.find_each.with_index do |event, idx|
      print "\r[#{idx + 1}/#{total}] " if (idx + 1) % 10 == 0
      
      begin
        lines = event.raw_text.lines.map(&:strip).reject(&:blank?)
        
        # Check if line 1 is the header and line 2 is the subject
        if lines.length >= 2 && lines[0].match?(/\[(Auto|Manual) E-Mail\].*:/i) && lines[1].length > 5
          new_subject = lines[1]
          
          # Update metadata
          event.metadata['emailSubject'] = new_subject
          event.save!
          
          fixed += 1
        end
      rescue => e
        failed += 1
        Rails.logger.error "Failed to fix event #{event.id}: #{e.message}"
      end
    end
    
    puts "\n✅ Fixed #{fixed} email subjects"
    puts "❌ Failed: #{failed}" if failed > 0
    
    # Now resync unsub events to update their trigger email subjects
    puts "\n🔄 Resyncing unsub events to update trigger subjects..."
    
    unsubs = Event.where(event_type: 'unsub')
                  .where("metadata->'triggerEmail'->>'emailSubject' LIKE '%[Manual E-Mail]%' OR metadata->'triggerEmail'->>'emailSubject' LIKE '%[Auto E-Mail]%'")
    
    unsub_total = unsubs.count
    puts "Found #{unsub_total} unsub events to update"
    
    return if unsub_total == 0
    
    unsub_fixed = 0
    
    unsubs.find_each.with_index do |unsub, idx|
      print "\r[#{idx + 1}/#{unsub_total}] " if (idx + 1) % 10 == 0
      
      begin
        sent_at = unsub.metadata.dig('triggerEmail', 'sentAt')
        next unless sent_at
        
        # Find the trigger email event
        trigger_email = Event.where(
          lead: unsub.lead,
          event_type: 'email_sent',
          occurred_at: Time.parse(sent_at)
        ).first
        
        if trigger_email && trigger_email.metadata['emailSubject']
          # Update the unsub's trigger email subject
          unsub.metadata['triggerEmail']['emailSubject'] = trigger_email.metadata['emailSubject']
          unsub.save!
          unsub_fixed += 1
        end
      rescue => e
        Rails.logger.error "Failed to fix unsub #{unsub.id}: #{e.message}"
      end
    end
    
    puts "\n✅ Updated #{unsub_fixed} unsub trigger subjects"
  end
end
