namespace :signals do
  desc "Generate HausSignals for all leads"
  task generate: :environment do
    puts "[HausSignals] Starting signal generation..."
    puts "=" * 80
    
    GenerateHausSignals.run
    
    puts ""
    puts "[HausSignals] Done!"
  end

  desc "Show HausSignals statistics"
  task stats: :environment do
    puts "HausSignals Statistics"
    puts "=" * 80
    
    total = HausSignal.count
    active = HausSignal.active.count
    
    puts "Total signals: #{total}"
    puts "Active signals: #{active}"
    puts ""
    
    puts "By Signal Type:"
    by_type = HausSignal.active.group(:signal_type).count.sort_by { |k, v| -v }
    by_type.each do |type, count|
      label = HausSignal::SIGNAL_DEFINITIONS.dig(type, :label) || type.humanize
      icon = HausSignal::SIGNAL_DEFINITIONS.dig(type, :icon) || '🔔'
      puts "  #{icon} #{label}: #{count}"
    end
    
    puts ""
    puts "By Severity:"
    by_severity = HausSignal.active.group(:severity).count.sort_by do |severity, _|
      ['high', 'medium', 'low'].index(severity) || 999
    end
    by_severity.each do |severity, count|
      puts "  #{severity}: #{count}"
    end
    
    puts ""
    puts "By Agent (Top 10):"
    by_agent = HausSignal.active
                         .joins(:agent)
                         .group('agents.name')
                         .count
                         .sort_by { |k, v| -v }
                         .first(10)
    
    by_agent.each do |agent_name, count|
      puts "  #{agent_name}: #{count} signals"
    end
    
    puts ""
    puts "=" * 80

    # Validate signal health
    validate_signal_health
  end

  # Signal health monitoring helper
  def validate_signal_health
    active = HausSignal.where(status: "active")

    total = active.count
    puts "Active signals: #{total}"

    if total.zero?
      puts "WARN: Zero active signals – check generator / scheduling."
    elsif total > 10_000
      puts "WARN: Abnormally high signal count (#{total}) – may be spammy."
    end

    by_severity = active.group(:severity).count
    puts "By severity: #{by_severity.inspect}"
  end

  desc "Clear all inactive signals older than 30 days"
  task cleanup: :environment do
    cutoff = 30.days.ago
    
    old_signals = HausSignal.where(status: ['resolved', 'dismissed'])
                             .where('last_seen_at < ?', cutoff)
    
    count = old_signals.count
    
    if count.zero?
      puts "No old signals to clean up."
    else
      puts "Deleting #{count} old signals (last seen before #{cutoff.to_date})..."
      old_signals.delete_all
      puts "Done!"
    end
  end
end
