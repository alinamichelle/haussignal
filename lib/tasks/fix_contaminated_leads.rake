namespace :haussignal do
  desc "Identify and fix leads with cross-contaminated call events"
  task fix_contaminated_leads: :environment do
    puts "🔍 Identifying leads with cross-contaminated call events..."
    puts ""
    
    contaminated_leads = []
    total_bad_events = 0
    
    Lead.where.not(timeline_synced_at: nil).find_each do |lead|
      bad_events = []
      
      lead.events.where(event_type: 'call').each do |event|
        next if event.raw_text.blank?
        next unless event.raw_text =~ /called/
        
        # Check if lead's name appears in the event
        has_first = lead.first_name.present? && event.raw_text.downcase.include?(lead.first_name.downcase)
        has_last = lead.last_name.present? && event.raw_text.downcase.include?(lead.last_name.downcase)
        
        unless has_first || has_last
          bad_events << event.id
          total_bad_events += 1
        end
      end
      
      if bad_events.any?
        contaminated_leads << {
          lofty_lead_id: lead.lofty_lead_id,
          full_name: lead.full_name,
          bad_event_count: bad_events.count,
          bad_event_ids: bad_events
        }
      end
    end
    
    puts "📊 Results:"
    puts "  Total contaminated leads: #{contaminated_leads.count}"
    puts "  Total bad events: #{total_bad_events}"
    puts ""
    
    if contaminated_leads.any?
      # Save lead IDs to file for re-scraping
      output_file = Rails.root.join('tmp/contaminated_leads.txt')
      File.write(output_file, contaminated_leads.map { |l| l[:lofty_lead_id] }.join("\n"))
      puts "✅ Contaminated lead IDs saved to: #{output_file}"
      puts ""
      
      # Show sample
      puts "📋 Sample contaminated leads (first 10):"
      contaminated_leads.first(10).each do |lead|
        puts "  - #{lead[:full_name]} (#{lead[:lofty_lead_id]}): #{lead[:bad_event_count]} bad events"
      end
      puts ""
      
      # Offer to delete bad events
      print "❓ Delete contaminated events now? (y/n): "
      response = STDIN.gets.chomp.downcase
      
      if response == 'y' || response == 'yes'
        puts ""
        puts "🗑️  Deleting contaminated events..."
        
        deleted_count = 0
        contaminated_leads.each do |lead_data|
          Event.where(id: lead_data[:bad_event_ids]).destroy_all
          deleted_count += lead_data[:bad_event_count]
        end
        
        puts "✅ Deleted #{deleted_count} contaminated events"
        puts ""
        puts "Next steps:"
        puts "  1. Re-scrape these leads: bin/rails lofty:sync_timelines"
        puts "  2. Use the lead IDs from: #{output_file}"
      else
        puts "⏭️  Skipping deletion. You can manually delete them later."
      end
    else
      puts "✅ No contaminated leads found!"
    end
  end
end
