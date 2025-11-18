namespace :debug do
  desc "Debug timeline entries for a lead"
  task :timeline, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails debug:timeline[LOFTY_LEAD_ID]"
      exit 1
    end

    puts "🔍 Debugging timeline for lead: #{args[:lofty_lead_id]}"
    scraper = Lofty::Scrapers::TimelineScraper.new
    entries = scraper.scrape_all_for_lead(args[:lofty_lead_id])
    
    puts "\n📊 Found #{entries.length} total timeline entries\n"
    
    # Group by type code
    entries.group_by(&:type_code).each do |type_code, items|
      puts "\n" + "=" * 80
      puts "Type Code: #{type_code} (#{items.length} events)"
      puts "=" * 80
      
      items.first(3).each_with_index do |entry, idx|
        puts "\n--- Entry #{idx + 1} ---"
        puts "Event ID: #{entry.event_id}"
        puts "Timestamp: #{entry.timestamp_text}"
        puts "Raw Text: #{entry.raw_text[0..150]}"
        puts "Data Attributes: #{entry.data_attributes.inspect}"
        puts "CSS Classes: #{entry.css_classes.inspect}"
        puts "HTML (first 200 chars): #{entry.html_content[0..200]}" if entry.html_content
        
        # Test classification
        classifier = Lofty::EmailClassifier
        puts "Is Email Sent?: #{classifier.is_email_sent?(entry.type_code)}"
        puts "Is Email Opened?: #{classifier.is_email_opened?(entry.type_code)}"
        puts "Classified Type: #{classifier.classify_email_type(entry)}"
        puts "Extracted Subject: #{classifier.extract_email_subject(entry)}"
        puts "Extracted Email ID: #{classifier.extract_email_id(entry)}"
      end
    end
  end
end
