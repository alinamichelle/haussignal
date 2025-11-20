namespace :emails do
  desc "Tag all email_sent events with categories based on subject line"
  task tag_categories: :environment do
    puts "🏷️  Tagging email events with categories..."
    puts ""
    
    email_events = Event.where(event_type: 'email_sent')
    total = email_events.count
    
    puts "Found #{total} email_sent events to process"
    puts ""
    
    tagged_count = 0
    category_counts = Hash.new(0)
    
    email_events.find_each.with_index do |event, index|
      subject = event.metadata['emailSubject']
      
      if subject.present?
        lofty_type = event.metadata['emailType']
        category = Lofty::EmailCategoryClassifier.classify(subject, lofty_type)
        
        if category
          event.update_column(:email_category, category)
          tagged_count += 1
          category_counts[category] += 1
        end
      end
      
      # Progress update every 1000 events
      if (index + 1) % 1000 == 0
        puts "  Processed #{index + 1}/#{total} events..."
      end
    end
    
    puts ""
    puts "✅ Complete!"
    puts "  Tagged: #{tagged_count} events"
    puts "  Uncategorized: #{total - tagged_count} events"
    puts ""
    puts "📊 Category breakdown:"
    category_counts.sort_by { |_, count| -count }.each do |category, count|
      category_name = Lofty::EmailCategoryClassifier.category_name(category)
      puts "  #{category_name}: #{count} events"
    end
  end
end
