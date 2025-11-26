namespace :events do
  desc "Health check for canonical event classification"
  task canonical_health_check: :environment do
    puts "Canonical Classification Health Check"
    puts "=" * 80
    puts "Run: #{Time.current}"
    puts ""
    
    # Check for unclassified events
    unclassified = Event.where(category: nil).or(Event.where(channel: nil)).count
    total = Event.count
    
    if unclassified > 0
      puts "⚠️  WARNING: #{unclassified} events missing classification"
      puts "   Total events: #{total}"
      puts "   Unclassified: #{unclassified} (#{(unclassified.to_f / total * 100).round(2)}%)"
      puts ""
      
      # Show breakdown by type_code
      puts "Unclassified by type_code:"
      Event.where(category: nil).or(Event.where(channel: nil))
        .group(:type_code)
        .count
        .sort_by { |k, v| -v }
        .first(10)
        .each do |type_code, count|
          puts "  Type #{type_code}: #{count} events"
        end
      
      exit 1  # Non-zero exit for monitoring/alerting
    else
      puts "✅ All events classified"
      puts "   Total events: #{total}"
      puts ""
    end
    
    # Show recent classification stats (last 24 hours)
    recent = Event.where('created_at > ?', 24.hours.ago)
    recent_count = recent.count
    recent_unclassified = recent.where(category: nil).or(recent.where(channel: nil)).count
    
    puts "Recent Activity (last 24 hours):"
    puts "  New events: #{recent_count}"
    puts "  Unclassified: #{recent_unclassified}"
    
    if recent_count > 0
      puts "  Classification rate: #{((recent_count - recent_unclassified).to_f / recent_count * 100).round(1)}%"
    end
    
    puts ""
    puts "=" * 80
    puts "Health check complete"
  end
end
