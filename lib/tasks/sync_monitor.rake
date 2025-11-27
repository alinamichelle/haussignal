namespace :sync do
  desc "Monitor sync progress in real-time"
  task monitor: :environment do
    puts "🔍 HausSignal Sync Monitor"
    puts "=========================="
    puts "Press Ctrl+C to stop monitoring"
    puts ""

    loop do
      system('clear') || system('cls')

      puts "🔍 HausSignal Sync Monitor - #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}"
      puts "=" * 60
      puts ""

      # Overall stats
      total_leads = Lead.count
      total_synced = Lead.where.not(timeline_synced_at: nil).count
      total_remaining = total_leads - total_synced
      overall_percent = ((total_synced.to_f / total_leads) * 100).round(1)

      puts "📊 OVERALL PROGRESS"
      puts "   #{total_synced} / #{total_leads} leads synced (#{overall_percent}%)"
      puts "   #{total_remaining} remaining"
      puts ""

      # Per-slot breakdown
      puts "📋 SLOT BREAKDOWN"
      (0..3).each do |slot|
        slot_total = Lead.where(sync_slot: slot).count
        slot_remaining = Lead.where(sync_slot: slot, timeline_synced_at: nil).count
        slot_synced = slot_total - slot_remaining
        slot_percent = ((slot_synced.to_f / slot_total) * 100).round(1)

        # Get last sync time and calculate time since
        latest_sync = Lead.where(sync_slot: slot).where.not(timeline_synced_at: nil).order(:timeline_synced_at).last
        if latest_sync
          time_since = Time.current - latest_sync.timeline_synced_at
          time_since_str = if time_since < 120
            "#{time_since.to_i}s ago"
          elsif time_since < 3600
            "#{(time_since / 60).to_i}m ago"
          else
            "#{(time_since / 3600).to_i}h ago"
          end
          status = time_since < 300 ? "🟢 ACTIVE" : time_since < 900 ? "🟡 SLOW" : "🔴 STUCK"
        else
          time_since_str = "Never"
          status = "⚪ PENDING"
        end

        puts "   Slot #{slot}: #{slot_synced}/#{slot_total} (#{slot_percent.to_s.rjust(5)}%) #{status.ljust(10)} Last: #{time_since_str}"
      end

      puts ""

      # Recent activity (last 10 minutes)
      puts "⚡ RECENT ACTIVITY (Last 10 minutes)"
      recent_cutoff = 10.minutes.ago
      recent_total = 0
      (0..3).each do |slot|
        recent_count = Lead.where(sync_slot: slot).where('timeline_synced_at > ?', recent_cutoff).count
        recent_total += recent_count
        activity_indicator = recent_count > 0 ? "✅" : "❌"
        puts "   Slot #{slot}: #{recent_count.to_s.rjust(2)} leads #{activity_indicator}"
      end

      puts "   Total: #{recent_total} leads in last 10 minutes"
      puts ""

      # Estimated completion
      if recent_total > 0
        rate_per_minute = recent_total / 10.0
        minutes_remaining = (total_remaining / rate_per_minute).round
        completion_time = Time.current + minutes_remaining.minutes
        puts "🎯 ESTIMATED COMPLETION"
        puts "   Rate: #{rate_per_minute.round(1)} leads/minute"
        puts "   ETA: #{completion_time.strftime('%Y-%m-%d %H:%M UTC')} (#{minutes_remaining} minutes)"
      else
        puts "🎯 ESTIMATED COMPLETION"
        puts "   ⚠️  No recent activity - workers may be stuck"
      end

      puts ""
      puts "Refreshing in 30 seconds... (Ctrl+C to exit)"

      sleep 30
    end
  end

  desc "Quick sync status check"
  task status: :environment do
    puts "🔍 Quick Sync Status - #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}"
    puts "=" * 50

    # Per-slot status
    (0..3).each do |slot|
      slot_total = Lead.where(sync_slot: slot).count
      slot_remaining = Lead.where(sync_slot: slot, timeline_synced_at: nil).count
      slot_synced = slot_total - slot_remaining
      slot_percent = ((slot_synced.to_f / slot_total) * 100).round(1)

      # Recent activity
      recent_count = Lead.where(sync_slot: slot).where('timeline_synced_at > ?', 10.minutes.ago).count
      activity = recent_count > 0 ? "🟢" : "🔴"

      puts "Slot #{slot}: #{slot_synced}/#{slot_total} (#{slot_percent}%) #{activity}"
    end
  end

  desc "Find what's running the sync"
  task detective: :environment do
    puts "🕵️  Sync Detective Mode"
    puts "=" * 30

    # Check for local processes
    puts "🖥️  Local Processes:"
    local_processes = `ps aux | grep -i "lofty\\|sync_timeline" | grep -v grep`.strip
    if local_processes.empty?
      puts "   ❌ No local sync processes found"
    else
      puts "   ✅ Found local processes:"
      puts local_processes.split("\n").map { |line| "      #{line}" }.join("\n")
    end
    puts ""

    # Check recent syncs pattern
    puts "🕐 Recent Sync Pattern Analysis:"
    recent_syncs = Lead.where('timeline_synced_at > ?', 2.hours.ago)
                      .order(:timeline_synced_at)
                      .pluck(:timeline_synced_at, :sync_slot)

    if recent_syncs.empty?
      puts "   ❌ No recent syncs found"
    else
      puts "   📊 #{recent_syncs.count} syncs in last 2 hours"

      # Group by 15-minute intervals
      intervals = recent_syncs.group_by { |time, slot| (time.to_f / 900).floor * 900 }
      intervals.sort.last(8).each do |interval_start, syncs|
        time_str = Time.at(interval_start).strftime('%H:%M')
        slot_counts = syncs.group_by(&:last).transform_values(&:count)
        slots_active = slot_counts.keys.sort.join(',')
        puts "   #{time_str}: #{syncs.count} syncs (slots: #{slots_active})"
      end
    end

    puts ""
    puts "🔍 Recommendations:"

    # Check if all slots stopped around same time
    last_syncs = (0..3).map do |slot|
      Lead.where(sync_slot: slot).where.not(timeline_synced_at: nil).order(:timeline_synced_at).last&.timeline_synced_at
    end.compact

    if last_syncs.any? && (last_syncs.max - last_syncs.min) < 10.minutes
      puts "   ⚠️  All slots stopped within 10 minutes of each other"
      puts "   💡 This suggests a common issue (network, auth, rate limiting)"
      puts "   🔧 Check: Railway logs, Lofty login status, network connectivity"
    else
      puts "   ℹ️  Workers stopped at different times - likely individual issues"
      puts "   🔧 Check: Individual worker logs, memory usage, droplet status"
    end
  end
end