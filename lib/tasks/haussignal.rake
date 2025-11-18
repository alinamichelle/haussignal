namespace :haussignal do
  desc "Sync unsub events for a single lead (test)"
  task :sync_unsub_one, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails haussignal:sync_unsub_one[LOFTY_LEAD_ID]"
      exit 1
    end

    service = Lofty::Sync::UnsubEventSyncService.new
    service.sync_for_lead(args[:lofty_lead_id])
  end

  desc "Sync unsub events for multiple leads"
  task :sync_unsubs => :environment do
    # For Phase 0, you can hardcode a small list or pull from existing leads
    lofty_lead_ids = ENV['LEAD_IDS']&.split(',') || Lead.pluck(:lofty_lead_id)

    if lofty_lead_ids.empty?
      puts "❌ No leads found. Set LEAD_IDS env var or create leads first."
      puts "   Example: LEAD_IDS=123,456,789 bin/rails haussignal:sync_unsubs"
      exit 1
    end

    service = Lofty::Sync::UnsubEventSyncService.new
    service.sync_for_multiple_leads(lofty_lead_ids)
  end
end

namespace :unsub do
  desc "Generate unsub report"
  task report: :environment do
    unsubs = Event.where(event_type: :unsub)
                  .includes(:lead, :agent)
                  .order(occurred_at: :desc)

    puts "\n" + "=" * 60
    puts "📊 UNSUB REPORT"
    puts "=" * 60
    puts "\nTotal unsubs: #{unsubs.count}"

    if unsubs.any?
      puts "\n📋 By category:"
      category_counts = unsubs.pluck("metadata->>'unsub_category'").compact.tally
      category_counts.sort_by { |k, v| -v }.each do |category, count|
        puts "  #{category.ljust(20)} #{count}"
      end

      puts "\n👥 By agent:"
      agent_counts = unsubs.group_by(&:agent).transform_values(&:count)
      agent_counts.sort_by { |k, v| -v }.each do |agent, count|
        agent_name = agent&.name || 'Unassigned'
        puts "  #{agent_name.ljust(20)} #{count}"
      end

      puts "\n🕒 Recent unsubs (last 10):"
      unsubs.limit(10).each do |event|
        lead_name = event.lead.full_name || event.lead.email || event.lead.lofty_lead_id
        category = event.metadata['unsub_category'] || 'unknown'
        puts "  #{event.occurred_at.strftime('%Y-%m-%d %H:%M')} | #{lead_name.ljust(25)} | #{category}"
      end
    end

    puts "\n" + "=" * 60
  end
end
