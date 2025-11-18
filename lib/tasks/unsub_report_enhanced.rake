namespace :unsub do
  desc "Enhanced unsub report with email engagement stats"
  task report_enhanced: :environment do
    unsubs = Event.where(event_type: :unsub)
                  .includes(:lead, :agent)
                  .order(occurred_at: :desc)

    puts "\n" + "=" * 100
    puts "📊 ENHANCED UNSUB REPORT"
    puts "=" * 100
    
    if unsubs.empty?
      puts "\nNo unsub events found."
      puts "=" * 100
      return
    end
    
    # Group unsubs by lead + timestamp (same unsub event creates multiple entries)
    unsub_events = unsubs.group_by { |e| [e.lead_id, e.occurred_at.to_i] }
    
    puts "\nTotal unique unsub events: #{unsub_events.count}"
    puts "Total unsub records: #{unsubs.count}"
    
    puts "\n" + "-" * 100
    puts "UNSUB DETAILS"
    puts "-" * 100
    
    unsub_events.each do |(lead_id, timestamp), events|
      event = events.first # Use first event for the metadata
      lead = event.lead
      lead_name = lead.full_name || lead.email || lead.lofty_lead_id
      
      # Categories this lead unsubscribed from
      categories = events.map { |e| e.metadata['unsubCategory'] || e.metadata['unsub_category'] }.compact.uniq
      
      puts "\n" + "─" * 100
      puts "Lead: #{lead_name}"
      puts "Unsubscribed: #{event.occurred_at.strftime('%b %d, %Y at %I:%M %p')}"
      puts "Categories: #{categories.join(', ')}"
      
      # Trigger email details
      trigger_email = event.metadata['triggerEmail']
      if trigger_email
        puts "\n📧 TRIGGER EMAIL:"
        puts "  Header:     #{trigger_email['emailHeader']}"
        puts "  Subject:    #{trigger_email['emailSubject']}"
        puts "  Type:       #{trigger_email['emailType']}"
        puts "  Sent:       #{Time.parse(trigger_email['sentAt']).strftime('%b %d at %I:%M %p') rescue trigger_email['sentAt']}"
        puts "  Status:     #{trigger_email['openStatus'] == 'opened' ? '✅ Opened' : '❌ Not Opened'}"
        
        if trigger_email['secondsFromSendToUnsub']
          minutes = (trigger_email['secondsFromSendToUnsub'] / 60.0).round(1)
          puts "  Timing:     Unsubscribed #{minutes} minutes after receiving"
        end
        
        if trigger_email['openStatus'] == 'opened' && trigger_email['secondsFromOpenToUnsub']
          minutes = (trigger_email['secondsFromOpenToUnsub'] / 60.0).round(1)
          puts "  Open→Unsub: #{minutes} minutes"
        end
      else
        puts "\n⚠️  No trigger email found"
      end
      
      # Get all email events for this lead to calculate engagement stats
      email_sent_events = Event.where(lead_id: lead_id, event_type: :email_sent)
      email_opened_events = Event.where(lead_id: lead_id, event_type: :email_opened)
      
      puts "\n📊 LEAD EMAIL ENGAGEMENT:"
      
      if email_sent_events.any?
        total_sent = email_sent_events.count
        total_opened = email_opened_events.count
        
        puts "  Total emails sent:    #{total_sent}"
        puts "  Total emails opened:  #{total_opened}"
        
        if total_sent > 0
          overall_open_rate = (total_opened.to_f / total_sent * 100).round(1)
          puts "  Overall open rate:    #{overall_open_rate}%"
        end
        
        # Group by email type
        sent_by_type = email_sent_events.group_by { |e| e.metadata['emailType'] || 'unknown' }
        
        puts "\n  By email type:"
        sent_by_type.each do |email_type, sent_events|
          type_sent_count = sent_events.count
          
          # Use EmailOpenMatcher to count actual matched opens
          type_opened_count = 0
          sent_events.each do |sent_event|
            matcher = Lofty::Matchers::EmailOpenMatcher.new(sent_event, email_opened_events)
            type_opened_count += 1 if matcher.call.present?
          end
          
          type_open_rate = type_sent_count > 0 ? (type_opened_count.to_f / type_sent_count * 100).round(1) : 0
          
          puts "    #{email_type.ljust(20)} Sent: #{type_sent_count.to_s.rjust(2)} | Opened: #{type_opened_count.to_s.rjust(2)} | Rate: #{type_open_rate}%"
        end
      else
        puts "  💡 No email events synced yet. Run: bin/rails haussignal:sync_emails_one[#{lead.lofty_lead_id}]"
      end
    end
    
    puts "\n" + "=" * 100
    puts "\n📈 SUMMARY INSIGHTS"
    puts "-" * 100
    
    # Email types causing unsubs
    email_types = unsubs.map { |e| e.metadata.dig('triggerEmail', 'emailType') }.compact
    if email_types.any?
      type_counts = email_types.tally.sort_by { |k, v| -v }
      puts "\nEmail types causing unsubs:"
      type_counts.each do |type, count|
        percentage = (count.to_f / email_types.length * 100).round(1)
        puts "  #{type.ljust(20)} #{count.to_s.rjust(3)} (#{percentage}%)"
      end
    end
    
    # Open behavior
    open_statuses = unsubs.map { |e| e.metadata.dig('triggerEmail', 'openStatus') }.compact
    if open_statuses.any?
      opened_count = open_statuses.count('opened')
      not_opened_count = open_statuses.count('not_opened')
      puts "\nOpen behavior before unsubbing:"
      puts "  Opened:     #{opened_count.to_s.rjust(3)} (#{(opened_count.to_f / open_statuses.length * 100).round(1)}%)"
      puts "  Not opened: #{not_opened_count.to_s.rjust(3)} (#{(not_opened_count.to_f / open_statuses.length * 100).round(1)}%)"
    end
    
    # Timing patterns
    timing_contexts = unsubs.map { |e| e.metadata.dig('triggerEmail', 'unsubContext', 'unsubTiming') }.compact
    if timing_contexts.any?
      timing_counts = timing_contexts.tally.sort_by { |k, v| -v }
      puts "\nTiming patterns:"
      timing_counts.each do |timing, count|
        puts "  #{timing.ljust(15)} #{count}"
      end
    end
    
    puts "\n" + "=" * 100
  end
end
