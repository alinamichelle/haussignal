namespace :events do
  desc "Backfill canonical fields for existing events"
  task backfill_canonical: :environment do
    puts "Starting canonical fields backfill..."
    puts "=" * 80
    
    # Count total events needing backfill
    total = Event.where(category: nil).count
    puts "Total events to backfill: #{total}"
    
    if total == 0
      puts "No events need backfilling. All done!"
      exit 0
    end
    
    # Track progress
    processed = 0
    updated = 0
    skipped = 0
    errors = 0
    
    # Process in batches
    batch_size = 1000
    start_time = Time.current
    
    Event.where(category: nil).find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |event|
        begin
          # Classify the event
          canonical = Lofty::CanonicalClassifier.classify(
            type_code: event.type_code,
            raw_text: event.raw_text || "",
            parsed_event: {}
          )
          
          # Update the event
          event.update_columns(
            category: canonical[:category],
            channel: canonical[:channel],
            auto: canonical[:auto] == false ? false : true,  # Ensure boolean
            direction: canonical[:direction],
            marketing_kind: canonical[:marketing_kind],
            communication_kind: canonical[:communication_kind],
            task_origin: canonical[:task_origin],
            smart_plan_step_kind: canonical[:smart_plan_step_kind],
            profile_change_type: canonical[:profile_change_type]
          )
          
          updated += 1
        rescue => e
          errors += 1
          Rails.logger.error "[Backfill] Failed to classify event #{event.id}: #{e.message}"
        end
        
        processed += 1
        
        # Progress report every 5000 events
        if processed % 5000 == 0
          elapsed = Time.current - start_time
          rate = processed / elapsed
          remaining = total - processed
          eta = remaining / rate
          
          puts "\nProgress: #{processed}/#{total} (#{(processed.to_f / total * 100).round(1)}%)"
          puts "  Updated: #{updated}"
          puts "  Errors: #{errors}"
          puts "  Rate: #{rate.round(1)} events/sec"
          puts "  ETA: #{(eta / 60).round(1)} minutes"
        end
      end
    end
    
    elapsed = Time.current - start_time
    
    puts "\n" + "=" * 80
    puts "Backfill completed!"
    puts "Total processed: #{processed}"
    puts "Successfully updated: #{updated}"
    puts "Errors: #{errors}"
    puts "Time elapsed: #{(elapsed / 60).round(1)} minutes"
    puts "Average rate: #{(processed / elapsed).round(1)} events/sec"
  end
  
  desc "Show canonical field distribution after backfill"
  task canonical_stats: :environment do
    puts "Canonical Fields Statistics"
    puts "=" * 80
    
    total = Event.count
    classified = Event.where.not(category: nil).count
    
    puts "Total events: #{total}"
    puts "Classified events: #{classified} (#{(classified.to_f / total * 100).round(1)}%)"
    puts "Unclassified events: #{total - classified}"
    puts ""
    
    puts "Category distribution:"
    Event.where.not(category: nil).group(:category).count.sort_by { |k, v| -v }.each do |category, count|
      puts "  #{category}: #{count} (#{(count.to_f / classified * 100).round(1)}%)"
    end
    
    puts ""
    puts "Channel distribution:"
    Event.where.not(channel: nil).group(:channel).count.sort_by { |k, v| -v }.each do |channel, count|
      puts "  #{channel}: #{count} (#{(count.to_f / classified * 100).round(1)}%)"
    end
    
    puts ""
    puts "Auto vs Manual:"
    auto_count = Event.where(auto: true).count
    manual_count = Event.where(auto: false).count
    puts "  Auto: #{auto_count} (#{(auto_count.to_f / total * 100).round(1)}%)"
    puts "  Manual: #{manual_count} (#{(manual_count.to_f / total * 100).round(1)}%)"
  end
end
