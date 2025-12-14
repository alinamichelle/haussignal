namespace :haussignal do
  desc "Scrape timeline for a single lead (raw test)"
  task :scrape_timeline_one_lead, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails haussignal:scrape_timeline_one_lead[LOFTY_LEAD_ID]"
      exit 1
    end

    puts "🔍 Scraping timeline for lead: #{args[:lofty_lead_id]}"
    scraper = Lofty::Scrapers::TimelineScraper.new
    result = scraper.scrape_all_for_lead(args[:lofty_lead_id])

    # Handle new scraper return format
    if result.is_a?(Hash)
      if !result[:success]
        puts "❌ Scraper failed: #{result[:message]}"
        exit 1
      end
      entries = result[:entries] || []
      puts "✅ Scraper succeeded: #{result[:message]}"
    else
      entries = Array(result)
      puts "⚠️  Using legacy scraper format"
    end

    puts "\n📊 Found #{entries.length} total timeline entries"
    
    # Group by type
    by_type = entries.group_by(&:type_code).transform_values(&:count)
    puts "\n📋 By type code:"
    by_type.sort_by { |k, v| -v }.each do |type_code, count|
      puts "  #{type_code.to_s.ljust(5)} → #{count} events"
    end
    
    # Show unsub events
    unsubs = entries.select { |e| e.type_code == 113 }
    if unsubs.any?
      puts "\n🚫 Unsub events found: #{unsubs.length}"
      unsubs.first(5).each do |unsub|
        puts "  - #{unsub.timestamp_text}: #{unsub.raw_text[0..80]}"
      end
    end
  end

  desc "Sync unsub events for a single lead (test)"
  task :sync_unsub_one, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails haussignal:sync_unsub_one[LOFTY_LEAD_ID]"
      exit 1
    end

    service = Lofty::Sync::UnsubEventSyncService.new
    service.sync_for_lead(args[:lofty_lead_id])
  end

  desc "Sync unsub events for multiple leads"
  task :sync_unsubs => :environment do
    # For Phase 0, you can hardcode a small list or pull from existing leads
    lofty_lead_ids = ENV['LEAD_IDS']&.split(',') || Lead.pluck(:lofty_lead_id)

    if lofty_lead_ids.empty?
      puts "❌ No leads found. Set LEAD_IDS env var or create leads first."
      puts "   Example: LEAD_IDS=123,456,789 bin/rails haussignal:sync_unsubs"
      exit 1
    end

    service = Lofty::Sync::UnsubEventSyncService.new
    service.sync_for_multiple_leads(lofty_lead_ids)
  end
  
  desc "Sync email events (sent/opened) for a single lead"
  task :sync_emails_one, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails haussignal:sync_emails_one[LOFTY_LEAD_ID]"
      exit 1
    end

    service = Lofty::Sync::EmailEventSyncService.new
    service.sync_for_lead(args[:lofty_lead_id])
  end
  
  desc "Scrape lead details (pipeline, tasks, family, referral)"
  task :scrape_lead_details, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails haussignal:scrape_lead_details[LOFTY_LEAD_ID]"
      exit 1
    end

    scraper = Lofty::Scrapers::LeadDetailsScraper.new
    details = scraper.scrape_lead_details(args[:lofty_lead_id])
    
    puts "\n" + "=" * 80
    puts "LEAD DETAILS FOR: #{args[:lofty_lead_id]}"
    puts "=" * 80
    puts "\nPipeline: #{details[:pipeline] || '(not found)'}"
    puts "Segment: #{details[:segment] || '(not found)'}"
    puts "Referral Source: #{details[:referral_source] || '(not found)'}"
    puts "Reg Date: #{details[:reg_date] || '(not found)'}"
    
    puts "\n" + "-" * 80
    puts "TASKS (#{details[:tasks].length})"
    puts "-" * 80
    details[:tasks].each_with_index do |task, idx|
      puts "\n#{idx + 1}. #{task[:name]}"
      puts "   Description: #{task[:description]}" if task[:description].present?
      puts "   Agent: #{task[:agent]}" if task[:agent].present?
      puts "   Role: #{task[:role]}" if task[:role].present?
    end
    
    puts "\n" + "-" * 80
    puts "FAMILY MEMBERS (#{details[:family_members].length})"
    puts "-" * 80
    details[:family_members].each do |member|
      puts "  - #{member}"
    end
    
    puts "\n" + "=" * 80
  end
end

namespace :unsub do
  desc "Generate unsub report"
  task report: :environment do
    unsubs = Event.where(event_type: :unsub)
                  .includes(:lead, :agent)
                  .order(occurred_at: :desc)

    puts "\n" + "=" * 60
    puts "📊 UNSUB REPORT"
    puts "=" * 60
    puts "\nTotal unsubs: #{unsubs.count}"

    if unsubs.any?
      puts "\n📋 By category:"
      # Load in Ruby to avoid SQL injection warnings with user data
      categories = unsubs.map { |e| e.metadata['unsubCategory'] || e.metadata['unsub_category'] }.compact
      category_counts = categories.tally
      category_counts.sort_by { |k, v| -v }.each do |category, count|
        puts "  #{category.ljust(20)} #{count}"
      end

      puts "\n📨 Top offending subjects (campaigns with most unsubs):"
      # Try new format first
      subject_counts = unsubs.map { |e| e.metadata.dig('triggerEmail', 'emailSubject') }.compact.tally
      if subject_counts.empty?
        # Fallback to old format (also load in Ruby to avoid SQL injection warnings)
        subject_counts = unsubs.map { |e| e.metadata['unsubbedFromSubject'] }.compact.tally
      end
      
      if subject_counts.any?
        subject_counts.sort_by { |k, v| -v }.first(10).each do |subject, count|
          puts "  [#{count}x] #{subject[0..70]}"
        end
      else
        puts "  (No subjects captured - may need to refine email parsing)"
      end
      
      # Enhanced insights
      puts "\n🤖 AI Coaching Insights:"
      
      # Email type analysis
      email_types = unsubs.map { |e| e.metadata.dig('triggerEmail', 'emailType') }.compact
      if email_types.any?
        type_counts = email_types.tally.sort_by { |k, v| -v }
        puts "  Email types causing unsubs:"
        type_counts.each do |type, count|
          percentage = (count.to_f / email_types.length * 100).round(1)
          puts "    #{type.ljust(20)} #{count} (#{percentage}%)"
        end
      end
      
      # Open behavior
      open_statuses = unsubs.map { |e| e.metadata.dig('triggerEmail', 'openStatus') }.compact
      if open_statuses.any?
        opened_count = open_statuses.count('opened')
        not_opened_count = open_statuses.count('not_opened')
        puts "  \n  Open behavior:"
        puts "    Opened before unsub:     #{opened_count} (#{(opened_count.to_f / open_statuses.length * 100).round(1)}%)"
        puts "    Not opened before unsub: #{not_opened_count} (#{(not_opened_count.to_f / open_statuses.length * 100).round(1)}%)"
      end
      
      # Quick unsubs
      quick_unsubs = unsubs.select { |e| e.metadata.dig('triggerEmail', 'unsubContext', 'quickUnsubAfterOpen') }
      if quick_unsubs.any?
        puts "  \n  ⚡ Quick unsubs (within 5 min of opening): #{quick_unsubs.length}"
      end
      
      # Timing analysis
      timing_contexts = unsubs.map { |e| e.metadata.dig('triggerEmail', 'unsubContext', 'unsubTiming') }.compact
      if timing_contexts.any?
        timing_counts = timing_contexts.tally.sort_by { |k, v| -v }
        puts "  \n  Timing patterns:"
        timing_counts.each do |timing, count|
          puts "    #{timing.ljust(15)} #{count}"
        end
      end

      puts "\n👥 By agent:"
      agent_counts = unsubs.group_by(&:agent).transform_values(&:count)
      agent_counts.sort_by { |k, v| -v }.each do |agent, count|
        agent_name = agent&.name || 'Unassigned'
        puts "  #{agent_name.ljust(20)} #{count}"
      end
      
      # Data quality stats (check both old and new formats)
      missing_subjects = unsubs.count { |e| 
        e.metadata.dig('triggerEmail', 'emailSubject').blank? && e.metadata['unsubbedFromSubject'].blank?
      }
      missing_emails = unsubs.count { |e| 
        e.metadata.dig('triggerEmail', 'emailType').blank? && e.metadata['unsubbedFromType'].blank?
      }
      
      if missing_subjects > 0 || missing_emails > 0
        puts "\n⚠️  Data Quality:"
        puts "  Missing subjects: #{missing_subjects} (#{(missing_subjects.to_f / unsubs.count * 100).round(1)}%)"
        puts "  Missing email match: #{missing_emails} (#{(missing_emails.to_f / unsubs.count * 100).round(1)}%)"
      end

      puts "\n🕒 Recent unsubs (last 10):"
      unsubs.limit(10).each do |event|
        lead_name = event.lead.full_name || event.lead.email || event.lead.lofty_lead_id
        category = event.metadata['unsubCategory'] || event.metadata['unsub_category'] || 'unknown'
        
        # Try new format first, fallback to old format
        trigger_email = event.metadata['triggerEmail']
        if trigger_email
          subject = trigger_email['emailSubject']&.[](0..40) || '(no subject)'
          email_type = trigger_email['emailType'] || 'unknown'
          open_status = trigger_email['openStatus'] == 'opened' ? '👁️' : '❌'
          timing = if trigger_email['secondsFromSendToUnsub']
            "#{(trigger_email['secondsFromSendToUnsub'] / 60.0).round(0)}m"
          else
            '?'
          end
          
          puts "  #{event.occurred_at.strftime('%m-%d %H:%M')} | #{lead_name[0..18].ljust(20)} | #{open_status} #{timing.rjust(5)} | #{subject}"
        else
          # Fallback to old format
          subject = event.metadata['unsubbedFromSubject']&.[](0..40) || '(no subject)'
          puts "  #{event.occurred_at.strftime('%Y-%m-%d %H:%M')} | #{lead_name[0..20].ljust(22)} | #{subject}"
        end
      end
    end

    puts "\n" + "=" * 60
  end
end
