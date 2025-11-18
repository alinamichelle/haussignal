namespace :haussignal do
  desc "Scrape timeline for a single lead (raw test)"
  task :scrape_timeline_one_lead, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails haussignal:scrape_timeline_one_lead[LOFTY_LEAD_ID]"
      exit 1
    end

    puts "🔍 Scraping timeline for lead: #{args[:lofty_lead_id]}"
    scraper = Lofty::Scrapers::TimelineScraper.new
    entries = scraper.scrape_all_for_lead(args[:lofty_lead_id])
    
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
      category_counts = unsubs.pluck("metadata->>'unsub_category'").compact.tally
      category_counts.sort_by { |k, v| -v }.each do |category, count|
        puts "  #{category.ljust(20)} #{count}"
      end

      puts "\n📨 Top offending subjects (campaigns with most unsubs):"
      subject_counts = unsubs.pluck("metadata->>'unsubbedFromSubject'").compact.tally
      if subject_counts.any?
        subject_counts.sort_by { |k, v| -v }.first(10).each do |subject, count|
          puts "  [#{count}x] #{subject[0..70]}"
        end
      else
        puts "  (No subjects captured - may need to refine email parsing)"
      end

      puts "\n👥 By agent:"
      agent_counts = unsubs.group_by(&:agent).transform_values(&:count)
      agent_counts.sort_by { |k, v| -v }.each do |agent, count|
        agent_name = agent&.name || 'Unassigned'
        puts "  #{agent_name.ljust(20)} #{count}"
      end
      
      # Data quality stats
      missing_subjects = unsubs.count { |e| e.metadata['unsubbedFromSubject'].blank? }
      missing_emails = unsubs.count { |e| e.metadata['unsubbedFromType'].blank? }
      
      if missing_subjects > 0 || missing_emails > 0
        puts "\n⚠️  Data Quality:"
        puts "  Missing subjects: #{missing_subjects} (#{(missing_subjects.to_f / unsubs.count * 100).round(1)}%)"
        puts "  Missing email match: #{missing_emails} (#{(missing_emails.to_f / unsubs.count * 100).round(1)}%)"
      end

      puts "\n🕒 Recent unsubs (last 10):"
      unsubs.limit(10).each do |event|
        lead_name = event.lead.full_name || event.lead.email || event.lead.lofty_lead_id
        category = event.metadata['unsub_category'] || 'unknown'
        subject = event.metadata['unsubbedFromSubject']&.[](0..40) || '(no subject)'
        puts "  #{event.occurred_at.strftime('%Y-%m-%d %H:%M')} | #{lead_name[0..20].ljust(22)} | #{subject}"
      end
    end

    puts "\n" + "=" * 60
  end
end
