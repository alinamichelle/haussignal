# lib/tasks/batch_sync.rake
namespace :haussignal do
  desc "Scrape lead details + timeline/unsubs for all IDs in a file"
  task :sync_unsubs_from_file, [:file_path] => :environment do |t, args|
    file_path = args[:file_path]
    abort "Usage: bin/rails 'haussignal:sync_unsubs_from_file[tmp/unsub_leads_ids.txt]'" if file_path.blank?

    unless File.exist?(file_path)
      abort "File not found: #{file_path}"
    end

    ids = File.readlines(file_path).map(&:strip).reject(&:blank?)
    puts "📦 Loaded #{ids.size} lead IDs from #{file_path}"

    details_scraper = Lofty::Scrapers::LeadDetailsScraper.new
    unsub_sync      = Lofty::Sync::UnsubEventSyncService.new
    email_sync      = Lofty::Sync::EmailEventSyncService.new

    total   = ids.size
    success = 0
    failed  = []

    ids.each_with_index do |lead_id, idx|
      puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "🔄 [#{idx + 1}/#{total}] Syncing lead #{lead_id}"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      begin
        # 1) Scrape + save pipeline, segment, source, reg_date
        puts "  📋 Scraping lead details..."
        details_scraper.scrape_lead_details(lead_id)

        # 2) Scrape timeline + sync email events (sent/opened)
        puts "  📧 Syncing email events..."
        email_sync.sync_for_lead(lead_id)

        # 3) Scrape timeline + sync unsub events
        puts "  🚫 Syncing unsub events..."
        unsub_sync.sync_for_lead(lead_id)

        success += 1
        puts "  ✅ Complete for #{lead_id}"
      rescue => e
        failed << { id: lead_id, error: "#{e.class}: #{e.message}" }
        Rails.logger.error "[sync_unsubs_from_file] Failed #{lead_id}: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        puts "  ❌ Failed for #{lead_id}: #{e.class} - #{e.message}"
      end
    end

    puts "\n" + "=" * 50
    puts "✅ DONE syncing unsub leads"
    puts "   Successful: #{success}/#{total}"
    puts "   Failed:     #{failed.size}/#{total}"

    if failed.any?
      puts "\n⚠️ Failures:"
      failed.each do |f|
        puts "  - #{f[:id]} → #{f[:error]}"
      end
    end
  end
end
