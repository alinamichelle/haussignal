#!/usr/bin/env ruby

require_relative 'config/environment'

puts '🔍 DEBUGGING DOM STRUCTURE FOR TYPES 124 & 37'
puts '=' * 60

begin
  scraper = Lofty::Scrapers::TimelineScraper.new

  # Just inspect the DOM structure for Yayr's timeline
  lead_id = '1142032162531031' # Yayr

  require 'playwright'

  Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
    browser = playwright.chromium.launch(headless: false)  # Visible for debugging

    storage_state_path = Rails.root.join('tmp/lofty_storage_state.json')
    unless File.exist?(storage_state_path)
      puts "❌ Session state not found! Run: bin/rails lofty:login"
      exit 1
    end

    context = browser.new_context(storageState: storage_state_path.to_s)
    page = context.new_page

    url = "#{ENV['LOFTY_BASE_URL']}/admin/home/detail?leadId=#{lead_id}"
    puts "🔵 Loading: #{url}"

    page.goto(url, waitUntil: 'networkidle')
    page.wait_for_timeout(3000)

    # STEP 1: Check API data first
    puts "\n🌐 STEP 1: Checking API data..."
    api_timelines = scraper.send(:fetch_first_page_json, page, lead_id, url)
    puts "   ✅ API returned: #{api_timelines.length} events"

    api_124_37 = api_timelines.select { |item| [124, 37].include?(item['timelineType']) }
    puts "   🎯 Types 124/37 in API: #{api_124_37.length} events"

    if api_124_37.any?
      puts "   📝 Sample API event (Type #{api_124_37.first['timelineType']}):"
      puts "      ID: #{api_124_37.first['id']}"
      puts "      Note: #{api_124_37.first['note']&.length || 0} chars"
      puts "      Body: #{api_124_37.first['body']&.length || 0} chars"
      puts "      Raw JSON keys: #{api_124_37.first.keys.join(', ')}"
    end

    puts "\n📜 STEP 2: Loading full timeline via DOM..."
    scraper.send(:load_full_email_timeline, page)

    puts "\n🔍 STEP 3: ANALYZING DOM TIMELINE STRUCTURE..."

    # Extract detailed information about ALL timeline items, focusing on 124 & 37
    debug_info = page.evaluate(<<~JS)
      (() => {
        const items = document.querySelectorAll('.timeline-item');
        const results = [];

        for (let i = 0; i < items.length; i++) {
          const el = items[i];
          const typeCode = parseInt(el.getAttribute('data-timeline-type') || '0', 10);

          // Focus on problematic types but gather all for context
          if (typeCode === 124 || typeCode === 37 || results.length < 5) {
            const contentEl = el.querySelector('.timeline-content');
            const timeEl = el.querySelector('.timeline-time .time');

            results.push({
              index: i,
              typeCode: typeCode,
              timelineId: el.getAttribute('data-timeline-id'),

              // Content analysis
              hasContentElement: !!contentEl,
              contentInnerHTML: contentEl ? contentEl.innerHTML.substring(0, 200) + '...' : null,
              contentInnerText: contentEl ? contentEl.innerText.substring(0, 200) + '...' : null,
              contentChildren: contentEl ? Array.from(contentEl.children).map(child => child.tagName + '.' + child.className).join(', ') : null,

              // Timestamp analysis
              hasTimeElement: !!timeEl,
              timestampText: timeEl ? timeEl.innerText : null,

              // Overall element analysis
              elementHTML: el.outerHTML.substring(0, 500) + '...',
              cssClasses: Array.from(el.classList).join(', '),
              allAttributes: Array.from(el.attributes).map(attr => attr.name + '=' + attr.value).join(', ')
            });
          }
        }

        return results;
      })();
    JS

    puts "\n📊 FOUND #{debug_info.length} TIMELINE ITEMS FOR ANALYSIS:"

    debug_info.each_with_index do |item, idx|
      puts "\n" + "─" * 80
      puts "ITEM #{idx + 1}: TYPE #{item['typeCode']} (Timeline ID: #{item['timelineId']})"
      puts "─" * 80

      puts "✅ Has .timeline-content element: #{item['hasContentElement']}"
      puts "✅ Has .timeline-time .time element: #{item['hasTimeElement']}"
      puts "📝 Timestamp text: #{item['timestampText'] || 'NULL'}"
      puts "📝 Content innerHTML length: #{item['contentInnerHTML'] ? item['contentInnerHTML'].length : 'NULL'}"
      puts "📝 Content innerText length: #{item['contentInnerText'] ? item['contentInnerText'].length : 'NULL'}"

      if item['typeCode'] == 124 || item['typeCode'] == 37
        puts "\n🚨 PROBLEMATIC TYPE - DETAILED ANALYSIS:"
        puts "   Content children: #{item['contentChildren'] || 'NONE'}"
        puts "   CSS classes: #{item['cssClasses']}"
        puts "   All attributes: #{item['allAttributes']}"
        puts "   Element HTML preview: #{item['elementHTML']}"

        if item['contentInnerHTML']
          puts "   Content HTML: #{item['contentInnerHTML']}"
        end

        if item['contentInnerText']
          puts "   Content Text: #{item['contentInnerText']}"
        end
      end
    end

    puts "\n" + "=" * 60
    puts "DOM ANALYSIS COMPLETE!"

    browser.close
  end

rescue StandardError => e
  puts "❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end