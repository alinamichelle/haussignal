namespace :lofty do
  desc "Validate timeline sync results for a specific lead"
  task :validate_sync, [:lofty_lead_id] => :environment do |t, args|
    lofty_lead_id = args[:lofty_lead_id] || ENV['LEAD_ID']
    
    unless lofty_lead_id
      puts "❌ Please provide a lead ID:"
      puts "   bundle exec rake lofty:validate_sync[1234567890]"
      puts "   or LEAD_ID=1234567890 bundle exec rake lofty:validate_sync"
      exit 1
    end

    lead = Lead.find_by(lofty_lead_id: lofty_lead_id)
    unless lead
      puts "❌ Lead not found: #{lofty_lead_id}"
      exit 1
    end

    puts "\n" + "="*80
    puts "🧪 TIMELINE SYNC VALIDATION"
    puts "="*80
    puts "\nLead: #{lead.full_name} (#{lofty_lead_id})"
    puts "Last synced: #{lead.timeline_synced_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Never'}"
    puts "\n" + "-"*80

    # 1. Overall event count
    total_events = lead.events.count
    puts "\n📊 Total Events: #{total_events}"
    
    if total_events == 0
      puts "⚠️  No events found for this lead!"
      puts "   Run sync first: bundle exec rake lofty:sync_timelines LEAD_ID=#{lofty_lead_id}"
      exit 0
    end

    # 2. Event type breakdown
    puts "\n📋 Event Type Breakdown:"
    event_types = lead.events.group(:event_type).count.sort_by { |k, v| -v }
    event_types.each do |type, count|
      puts "   #{type.to_s.ljust(20)}: #{count}"
    end

    # 3. SMS validation
    puts "\n" + "-"*80
    puts "💬 SMS Validation:"
    sms_events = lead.events.where(event_type: :sms)
    puts "   Total SMS: #{sms_events.count}"
    
    if sms_events.any?
      sample_sms = sms_events.first
      body = sample_sms.metadata['sms_body']
      
      puts "   Sample SMS body:"
      puts "   " + "-"*40
      puts "   #{body&.[](0..200) || '(empty)'}"
      puts "   " + "-"*40
      
      # Check for truncation
      if body && body.length > 0
        puts "   ✅ SMS body captured (#{body.length} chars)"
      else
        puts "   ⚠️  SMS body is empty!"
      end
      
      # Check metadata completeness
      sms_with_direction = sms_events.where("metadata->>'sms_direction' IS NOT NULL").count
      sms_with_number = sms_events.where("metadata->>'virtual_number' IS NOT NULL").count
      
      puts "   SMS with direction: #{sms_with_direction}/#{sms_events.count}"
      puts "   SMS with number: #{sms_with_number}/#{sms_events.count}"
    else
      puts "   No SMS events found"
    end

    # 4. Call validation
    puts "\n" + "-"*80
    puts "📞 Call Validation:"
    call_events = lead.events.where(event_type: :call)
    puts "   Total Calls: #{call_events.count}"
    
    if call_events.any?
      sample_call = call_events.first
      
      puts "   Sample call metadata:"
      puts "     Direction: #{sample_call.metadata['call_direction'] || '(missing)'}"
      puts "     Duration: #{sample_call.metadata['call_duration_seconds'] || '(missing)'} seconds"
      puts "     Result: #{sample_call.metadata['call_result'] || '(missing)'}"
      puts "     Status: #{sample_call.metadata['call_status'] || '(missing)'}"
      puts "     Caller #: #{sample_call.metadata['caller_number'] || '(missing)'}"
      puts "     Virtual #: #{sample_call.metadata['virtual_number'] || '(missing)'}"
      puts "     Recording URL: #{sample_call.metadata['lofty_recording_url'] ? '✅ Present' : '❌ Missing'}"
      
      # Check completeness
      calls_with_recording = call_events.where("metadata->>'lofty_recording_url' IS NOT NULL").count
      calls_with_duration = call_events.where("metadata->>'call_duration_seconds' IS NOT NULL").count
      
      puts "\n   Calls with recording URL: #{calls_with_recording}/#{call_events.count}"
      puts "   Calls with duration: #{calls_with_duration}/#{call_events.count}"
    else
      puts "   No call events found"
    end

    # 5. Pipeline changes
    puts "\n" + "-"*80
    puts "🔄 Pipeline Changes:"
    pipeline_events = lead.events.where("metadata->>'activity_type' = 'pipeline_change'")
    puts "   Total: #{pipeline_events.count}"
    
    if pipeline_events.any?
      sample = pipeline_events.first
      from = sample.metadata['from']
      to = sample.metadata['to']
      
      puts "   Sample: \"#{from}\" → \"#{to}\""
      
      if from && to
        puts "   ✅ Both 'from' and 'to' captured"
      else
        puts "   ⚠️  Missing 'from' or 'to' values!"
      end
      
      complete_changes = pipeline_events.where("metadata->>'from' IS NOT NULL AND metadata->>'to' IS NOT NULL").count
      puts "   Complete changes: #{complete_changes}/#{pipeline_events.count}"
    else
      puts "   No pipeline changes found"
    end

    # 6. Tasks
    puts "\n" + "-"*80
    puts "✅ Task Validation:"
    task_events = lead.events.where(event_type: :note).where("metadata->>'task_title' IS NOT NULL")
    puts "   Total Tasks: #{task_events.count}"
    
    if task_events.any?
      sample = task_events.first
      puts "   Sample task:"
      puts "     Title: #{sample.metadata['task_title'] || '(missing)'}"
      puts "     Status: #{sample.metadata['task_status'] || '(missing)'}"
      puts "     Creator: #{sample.metadata['task_creator'] || '(missing)'}"
      puts "     Due date: #{sample.metadata['task_due_date'] || '(none)'}"
      
      tasks_with_status = task_events.where("metadata->>'task_status' IS NOT NULL").count
      puts "\n   Tasks with status: #{tasks_with_status}/#{task_events.count}"
    else
      puts "   No tasks found"
    end

    # 7. Smart plan activities
    puts "\n" + "-"*80
    puts "🤖 Smart Plan Activities:"
    smartplan_events = lead.events.where(event_type: :smartplan)
    puts "   Total: #{smartplan_events.count}"
    
    if smartplan_events.any?
      sample = smartplan_events.first
      puts "   Sample:"
      puts "     Plan name: #{sample.metadata['smartplan_name'] || '(missing)'}"
      puts "     Step name: #{sample.metadata['smartplan_step_name'] || '(missing)'}"
      puts "     Step type: #{sample.metadata['smartplan_step_type'] || '(missing)'}"
      puts "     Trigger: #{sample.metadata['smartplan_trigger'] || '(missing)'}"
    else
      puts "   No smart plan events found"
    end

    # 8. Website activity
    puts "\n" + "-"*80
    puts "🌐 Website Activity:"
    website_events = lead.events.where(event_type: :alert_view)
    puts "   Total: #{website_events.count}"
    
    if website_events.any?
      sample = website_events.first
      puts "   Sample:"
      puts "     Details: #{sample.metadata['activity_details']&.[](0..80) || '(missing)'}"
      puts "     Listing URL: #{sample.metadata['listing_url'] ? '✅ Present' : '❌ Missing'}"
      puts "     Listing ID: #{sample.metadata['listing_id'] || '(none)'}"
    else
      puts "   No website activity found"
    end

    # 9. Unknown event types
    puts "\n" + "-"*80
    puts "❓ Unknown Event Types:"
    unknown_events = lead.events.where(event_type: :other)
    puts "   Total: #{unknown_events.count}"
    
    if unknown_events.any?
      puts "   ⚠️  Found unknown events - these need investigation:"
      unknown_events.limit(5).each do |event|
        puts "     Type code: #{event.type_code}"
        puts "     Text: #{event.raw_text&.[](0..80)}"
        puts "     Has raw_html: #{event.metadata['raw_html'].present? ? '✅ Yes' : '❌ No'}"
        puts ""
      end
    else
      puts "   ✅ All event types recognized"
    end

    # 10. Timeline completeness check
    puts "\n" + "="*80
    puts "📊 COMPLETENESS SUMMARY"
    puts "="*80
    
    puts "\n✅ Events with complete metadata:"
    puts "   SMS bodies: #{lead.events.where(event_type: :sms).where("metadata->>'sms_body' IS NOT NULL").count}/#{lead.events.where(event_type: :sms).count}"
    puts "   Call recordings: #{lead.events.where(event_type: :call).where("metadata->>'lofty_recording_url' IS NOT NULL").count}/#{lead.events.where(event_type: :call).count}"
    puts "   Pipeline changes: #{lead.events.where("metadata->>'from' IS NOT NULL AND metadata->>'to' IS NOT NULL").count}/#{pipeline_events.count}"
    
    puts "\n⚠️  Events missing metadata:"
    missing_html = lead.events.where("metadata->>'raw_html' IS NULL").count
    puts "   Events without raw_html: #{missing_html}/#{total_events}"
    
    puts "\n" + "="*80
    puts "🎉 Validation complete!"
    puts "="*80
    puts "\n💡 Next steps:"
    puts "   1. Manually count timeline items in Lofty UI for this lead"
    puts "   2. Compare with total events (#{total_events})"
    puts "   3. If numbers don't match, check scraper scroll logic"
    puts "   4. If metadata is missing, update TimelineParser extractors"
    puts "\n"
  end
end
