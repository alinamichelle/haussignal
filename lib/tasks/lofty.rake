namespace :lofty do
  desc "Login to Lofty and save storage state"
  task login: :environment do
    require 'playwright'

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: false)
      context = browser.new_context
      page    = context.new_page

      puts "🔵 Opening Lofty..."
      page.goto(ENV['LOFTY_BASE_URL'])

      puts "🟡 Please log in manually. You have 60 seconds..."
      sleep 60

      context.storage_state(path: "tmp/lofty_storage_state.json")
      puts "🟢 Saved Lofty session → tmp/lofty_storage_state.json"

      browser.close
    end
  end

  desc "Sync Lofty timelines into events (incremental by default)"
  task sync_timelines: :environment do
    full       = ENV["FULL"] == "true"
    batch_size = (ENV["BATCH_SIZE"] || 50).to_i
    incremental = !full

    puts "🚀 Starting Lofty timeline sync"
    puts "   Mode: #{full ? 'FULL' : 'INCREMENTAL'}"
    puts "   Batch size: #{batch_size}"
    puts ""

    # Get leads to sync
    scope = Lead.where.not(lofty_lead_id: nil)

    unless full
      # Incremental: only sync leads that haven't been synced recently
      scope = scope.where("timeline_synced_at IS NULL OR timeline_synced_at < ?", 1.day.ago)
    end

    # Filter by sync slot if specified (for parallel workers)
    if ENV["SYNC_SLOT"].present?
      slot = ENV["SYNC_SLOT"].to_i
      scope = scope.where(sync_slot: slot)
      puts "   Sync slot: #{slot}"
    end

    total_leads = scope.count
    puts "📊 Found #{total_leads} leads to sync"

    if total_leads == 0
      puts "✅ No leads to sync!"
      exit
    end

    # Confirm before starting
    print "\n⚠️  This will scrape #{total_leads} leads. Continue? (y/n): "
    response = STDIN.gets.chomp.downcase
    unless response == 'y' || response == 'yes'
      puts "❌ Cancelled"
      exit
    end

    puts "\n🔄 Starting sync...\n"

    sync_service = Lofty::Sync::TimelineSyncService.new
    
    # Process in batches
    batches_processed = 0
    all_lead_ids = scope.pluck(:lofty_lead_id)
    
    all_lead_ids.each_slice(batch_size).with_index do |batch_lead_ids, batch_index|
      puts "\n" + "="*80
      puts "📦 Processing batch #{batch_index + 1}/#{(total_leads.to_f / batch_size).ceil}"
      puts "="*80 + "\n"
      
      begin
        sync_service.sync_for_multiple_leads(batch_lead_ids, incremental: incremental)
        batches_processed += 1
        
        # Restart scraper every 10 batches to prevent memory issues
        if batches_processed > 0 && batches_processed % 10 == 0
          puts "\n🔄 Restarting scraper after #{batches_processed} batches to prevent memory issues..."
          sync_service = Lofty::Sync::TimelineSyncService.new
        end
        
      rescue => e
        puts "\n❌ Batch #{batch_index + 1} failed: #{e.message}"
        puts "   Continuing with next batch..."
      end
    end

    puts "\n" + "="*80
    puts "🎉 Timeline sync complete!"
    puts "   Batches processed: #{batches_processed}"
    puts "   Total leads: #{total_leads}"
    puts "="*80
  end
end
