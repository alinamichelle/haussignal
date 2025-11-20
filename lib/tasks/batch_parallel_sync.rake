# lib/tasks/batch_parallel_sync.rake
require 'parallel'

namespace :haussignal do
  desc "FAST: Scrape lead details + timeline/unsubs for all IDs in a file using multiple workers"
  task :sync_unsubs_from_file_parallel, [:file_path, :workers] => :environment do |t, args|
    # Fix MacOS fork safety issue
    ENV['OBJC_DISABLE_INITIALIZE_FORK_SAFETY'] = 'YES'
    file_path = args[:file_path]
    worker_count = (args[:workers] || 10).to_i

    if file_path.blank?
      abort "Usage: bin/rails 'haussignal:sync_unsubs_from_file_parallel[tmp/unsub_leads_ids.txt,10]'"
    end

    unless File.exist?(file_path)
      abort "File not found: #{file_path}"
    end

    ids = File.readlines(file_path).map(&:strip).reject(&:blank?)
    total = ids.size

    puts "📦 Loaded #{total} lead IDs from #{file_path}"
    puts "🧵 Using #{worker_count} workers"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Track stats with thread-safe counter
    success_count = Concurrent::AtomicFixnum.new(0)
    failed_count = Concurrent::AtomicFixnum.new(0)
    failed_ids = Concurrent::Array.new

    start_time = Time.now

    Parallel.each_with_index(ids, in_processes: worker_count) do |lead_id, idx|
      # Each process gets its own Rails DB connection
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          puts "[PID #{Process.pid}] 🔄 [#{idx + 1}/#{total}] Syncing lead #{lead_id}"

          details_scraper = Lofty::Scrapers::LeadDetailsScraper.new
          email_sync      = Lofty::Sync::EmailEventSyncService.new
          unsub_sync      = Lofty::Sync::UnsubEventSyncService.new

          # 1) Scrape + persist pipeline/segment/source/reg_date
          details_scraper.scrape_lead_details(lead_id)

          # 2) Scrape + persist email events (sent/opened)
          email_sync.sync_for_lead(lead_id)

          # 3) Scrape + persist unsub events
          unsub_sync.sync_for_lead(lead_id)

          success_count.increment
          puts "[PID #{Process.pid}] ✅ Complete: #{lead_id}"
        rescue => e
          failed_count.increment
          failed_ids << { id: lead_id, error: "#{e.class}: #{e.message}" }
          Rails.logger.error "[sync_unsubs_from_file_parallel] Failed #{lead_id}: #{e.class} - #{e.message}"
          puts "[PID #{Process.pid}] ❌ Failed: #{lead_id} - #{e.message}"
        ensure
          ActiveRecord::Base.clear_active_connections!
        end
      end
    end

    elapsed = Time.now - start_time
    minutes = (elapsed / 60).round(1)

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "✅ PARALLEL SYNC COMPLETE"
    puts "   Total Time:  #{minutes} minutes"
    puts "   Successful:  #{success_count.value}/#{total}"
    puts "   Failed:      #{failed_count.value}/#{total}"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if failed_ids.any?
      puts "\n⚠️ Failures:"
      failed_ids.each do |f|
        puts "  - #{f[:id]} → #{f[:error]}"
      end
      
      # Write failed IDs to file for retry
      File.write("tmp/failed_sync_ids.txt", failed_ids.map { |f| f[:id] }.join("\n"))
      puts "\n💾 Failed IDs saved to tmp/failed_sync_ids.txt for retry"
    end
  end
end
