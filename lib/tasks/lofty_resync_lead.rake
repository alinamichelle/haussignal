namespace :lofty do
  desc "Resync a single lead's timeline events (deletes and re-scrapes)"
  task :resync_lead, [:lofty_lead_id] => :environment do |t, args|
    lofty_lead_id = args[:lofty_lead_id]
    
    if lofty_lead_id.blank?
      puts "❌ Usage: bin/rails lofty:resync_lead[LOFTY_LEAD_ID]"
      puts "   Example: bin/rails lofty:resync_lead[1127873289209658]"
      exit 1
    end
    
    lead = Lead.find_by(lofty_lead_id: lofty_lead_id)
    
    unless lead
      puts "❌ Lead not found with lofty_lead_id: #{lofty_lead_id}"
      exit 1
    end
    
    puts "🔄 Resyncing timeline for: #{lead.full_name} (#{lofty_lead_id})"
    puts "   Current event count: #{lead.events.count}"
    
    # Re-scrape timeline (NO DELETE - we'll upsert)
    puts "\n📡 Scraping timeline from Lofty..."
    scraper = Lofty::Scrapers::TimelineScraper.new
    entries = scraper.scrape_all_for_lead(lofty_lead_id)
    puts "   Scraped #{entries.length} timeline entries"
    
    # Track which event IDs we found in this scrape
    scraped_event_ids = Set.new
    
    puts "\n💾 Parsing and upserting events..."
    saved = 0
    updated = 0
    skipped = 0
    
    entries.each do |entry|
      parsed = Lofty::TimelineParser.parse(entry, lead: lead)
      
      if parsed
        scraped_event_ids << parsed[:lofty_timeline_id]
        
        event = Event.find_or_initialize_by(lofty_timeline_id: parsed[:lofty_timeline_id])
        is_new = event.new_record?
        
        event.assign_attributes(
          lead_id: lead.id,
          event_type: parsed[:event_type],
          type_code: parsed[:type_code],
          occurred_at: parsed[:occurred_at],
          raw_text: parsed[:raw_text],
          agent_id: parsed[:agent_id],
          metadata: parsed[:metadata],
          from_pipeline: parsed[:from_pipeline],
          to_pipeline: parsed[:to_pipeline],
          recording_available: parsed[:recording_available]
        )
        
        if event.save
          if is_new
            saved += 1
          else
            updated += 1
          end
        end
      else
        skipped += 1
      end
    end
    
    # Optional: Delete events that weren't in the new scrape (they were removed from Lofty)
    # Commented out for safety - uncomment if you want to remove stale events
    # deleted = lead.events.where.not(lofty_timeline_id: scraped_event_ids.to_a).destroy_all
    # puts "   Removed #{deleted.count} stale events"
    
    # Update sync timestamp
    lead.update(timeline_synced_at: Time.current)
    
    puts "\n✅ Resync complete!"
    puts "   New: #{saved} events"
    puts "   Updated: #{updated} events"
    puts "   Skipped: #{skipped} events"
    puts "   Total in DB: #{lead.events.count} events"
    puts "\n📊 Event breakdown:"
    
    lead.events.group(:event_type).count.sort_by { |k, v| -v }.each do |type, count|
      puts "   #{type.ljust(15)} #{count}"
    end
  end
end
