namespace :lofty do
  desc "Monitor for new/unknown type codes in recent events"
  task monitor_type_codes: :environment do
    puts "\n" + "="*80
    puts "🔍 LOFTY TYPE CODE MONITORING REPORT"
    puts "="*80
    puts "\n📅 Last 7 days activity\n\n"
    
    # Get all type codes from last 7 days
    recent_events = Event.where("created_at > ?", 7.days.ago)
    
    if recent_events.empty?
      puts "⚠️  No events created in the last 7 days"
      exit 0
    end
    
    puts "📊 Type Code Breakdown (Last 7 Days):\n\n"
    
    type_code_stats = recent_events
      .group(:type_code, :event_type)
      .select("type_code, event_type, COUNT(*) as count")
      .order("type_code ASC")
    
    type_code_stats.each do |stat|
      type_code = stat.type_code
      event_type = stat.event_type
      count = stat.count
      
      # Check if this is an unknown type
      is_unknown = event_type == 'other'
      marker = is_unknown ? "⚠️ " : "✅"
      
      puts "#{marker} Type Code #{type_code.to_s.ljust(4)} → #{event_type.ljust(20)} (#{count} events)"
      
      # Show sample for unknown types
      if is_unknown
        sample = Event.where(type_code: type_code, event_type: 'other').first
        if sample
          puts "     Sample: #{sample.raw_text.lines.first&.strip&.[](0..80)}"
        end
        puts ""
      end
    end
    
    # Summary of unknowns
    unknown_count = recent_events.where(event_type: 'other').count
    total_count = recent_events.count
    unknown_pct = (unknown_count.to_f / total_count * 100).round(1)
    
    puts "\n" + "-"*80
    puts "📈 SUMMARY:"
    puts "   Total events (7d): #{total_count}"
    puts "   Unknown events: #{unknown_count} (#{unknown_pct}%)"
    
    if unknown_count > 0
      puts "\n⚠️  ACTION REQUIRED:"
      puts "   #{unknown_count} events with type 'other' detected"
      puts "   Review samples above and update TimelineParser TYPE_CODE_MAPPINGS"
      puts "   File: app/services/lofty/timeline_parser.rb"
    else
      puts "\n✅ All event types recognized!"
    end
    
    # Check for new type codes not in mapping
    puts "\n" + "-"*80
    puts "🔎 TYPE CODE MAPPING CHECK:\n\n"
    
    # Get current mappings from parser
    require Rails.root.join('app/services/lofty/timeline_parser')
    known_codes = Lofty::TimelineParser::TYPE_CODE_MAPPINGS.keys
    
    all_codes = Event.distinct.pluck(:type_code).compact.sort
    unmapped_codes = all_codes - known_codes
    
    if unmapped_codes.any?
      puts "⚠️  Type codes NOT in TYPE_CODE_MAPPINGS:"
      unmapped_codes.each do |code|
        sample = Event.where(type_code: code).first
        event_type = sample.event_type
        puts "   #{code} → currently mapped to #{event_type}"
        puts "      Sample: #{sample.raw_text.lines.first&.strip&.[](0..60)}"
      end
      puts "\n   Consider adding these to TYPE_CODE_MAPPINGS if they should have explicit mapping"
    else
      puts "✅ All type codes are explicitly mapped"
    end
    
    puts "\n" + "="*80
    puts "🎉 Monitoring complete!"
    puts "="*80
    puts "\n💡 Run this daily or weekly to catch Lofty DOM changes early\n\n"
  end
  
  desc "Show type code distribution across all events"
  task type_code_stats: :environment do
    puts "\n" + "="*80
    puts "📊 ALL-TIME TYPE CODE STATISTICS"
    puts "="*80
    puts "\n"
    
    stats = Event.group(:type_code, :event_type).count.sort
    
    stats.each do |(type_code, event_type), count|
      puts "Type #{type_code.to_s.ljust(4)} | #{event_type.ljust(20)} | #{count.to_s.rjust(6)} events"
    end
    
    puts "\n" + "="*80
    total = Event.count
    puts "Total events: #{total}"
    puts "="*80
    puts "\n"
  end
end
