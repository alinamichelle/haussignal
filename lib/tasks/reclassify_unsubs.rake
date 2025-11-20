namespace :unsubs do
  desc "Reclassify all unsub events with updated email category classifier"
  task reclassify: :environment do
    puts "Starting reclassification of unsub events..."
    
    # Get all unsub events
    unsub_events = Event.where(event_type: ['unsub', 'manual_unsub'])
    total = unsub_events.count
    
    puts "Found #{total} unsub events to reclassify"
    
    updated = 0
    unsub_events.find_each.with_index do |event, index|
      # Get trigger email info
      trigger_subject = event.metadata.dig('triggerEmail', 'emailSubject')
      trigger_type = event.metadata.dig('triggerEmail', 'emailType')
      
      # Skip manual unsubs without trigger email
      if event.event_type == 'manual_unsub' && trigger_subject.blank?
        next
      end
      
      # Reclassify
      old_category = event.metadata['unsubCategory']
      new_category = if event.event_type == 'manual_unsub'
        'manual_unsub'
      else
        Lofty::EmailCategoryClassifier.classify(trigger_subject, trigger_type) || 'uncategorized'
      end
      
      # Update if changed
      if old_category != new_category
        event.metadata['unsubCategory'] = new_category
        event.save!
        updated += 1
        subject_display = trigger_subject.present? ? trigger_subject.truncate(60) : '(no subject)'
        puts "[#{index + 1}/#{total}] Updated: #{subject_display} | #{old_category} → #{new_category}"
      end
      
      # Progress update every 100
      if (index + 1) % 100 == 0
        puts "Progress: #{index + 1}/#{total} (#{updated} updated)"
      end
    end
    
    puts "\n✅ Reclassification complete!"
    puts "Total events: #{total}"
    puts "Updated: #{updated}"
    puts "Unchanged: #{total - updated}"
  end
end
