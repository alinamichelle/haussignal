# lib/tasks/lead_details_backfill.rake
namespace :haussignal do
  desc "Backfill pipeline/segment/source/reg_date for lead IDs in a file"
  task :backfill_lead_details_from_file, [:file_path] => :environment do |t, args|
    file_path = args[:file_path]
    abort "Usage: bin/rails 'haussignal:backfill_lead_details_from_file[tmp/unsub_leads.txt]'" if file_path.blank?

    unless File.exist?(file_path)
      abort "File not found: #{file_path}"
    end

    ids = File.readlines(file_path).map(&:strip).reject(&:blank?)
    puts "📦 Loaded #{ids.size} lead IDs from #{file_path}"

    scraper = Lofty::Scrapers::LeadDetailsScraper.new
    total   = ids.size
    success = 0
    failed  = []

    ids.each_with_index do |lead_id, idx|
      puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "🔄 [#{idx + 1}/#{total}] Backfilling lead #{lead_id}"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      begin
        scraper.scrape_lead_details(lead_id)
        success += 1
      rescue => e
        failed << { id: lead_id, error: "#{e.class}: #{e.message}" }
        Rails.logger.error "[backfill_lead_details] Failed #{lead_id}: #{e.class} - #{e.message}"
        puts "❌ Failed for #{lead_id}: #{e.class} - #{e.message}"
      end
    end

    puts "\n✅ DONE"
    puts "   Successful: #{success}"
    puts "   Failed:     #{failed.size}"

    if failed.any?
      puts "\n⚠️ Failures:"
      failed.each do |f|
        puts "  - #{f[:id]} → #{f[:error]}"
      end
    end
  end
end
