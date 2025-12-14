#!/usr/bin/env ruby

require_relative 'config/environment'

puts '🚀 FORCING FULL TIMELINE LOAD FOR YAYR'
puts '=' * 60

begin
  require 'playwright'

  lead_id = '1142032162531031' # Yayr

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
    page.wait_for_timeout(5000)

    puts "\n🧵 Starting AGGRESSIVE timeline loading..."

    # Wait for timeline to exist
    page.wait_for_selector('.timeline-load-wrap', timeout: 15_000)
    puts "✅ Timeline container found"

    # Try multiple aggressive strategies
    last_count = 0
    total_iterations = 0

    300.times do |i|  # Increased from 100 to 300
      total_iterations += 1

      # Get current count
      items = page.locator('.timeline-item')
      count = items.count

      if count > last_count
        puts "   [#{i+1}] 📥 +#{count - last_count} new items (total: #{count})"
        last_count = count
      elsif i % 10 == 0
        puts "   [#{i+1}] 🔄 stable, items=#{count}"
      end

      # Strategy 1: Scroll to last item
      if count > 0
        items.nth(count - 1).scroll_into_view_if_needed
      end

      # Strategy 2: Click load-more buttons more aggressively
      begin
        load_buttons = page.locator('.new-timeline-bottom-btn, .timeline-bottom-btn, button:has-text("Load"), button:has-text("More"), .load-more')
        if load_buttons.count > 0
          load_buttons.first.scroll_into_view_if_needed
          if load_buttons.first.visible?
            puts "   🔽 Clicking load-more button..."
            load_buttons.first.click
            page.wait_for_timeout(5000)  # Longer wait
          end
        end
      rescue => e
        # Ignore button click errors
      end

      # Strategy 3: Scroll to absolute bottom of page
      page.evaluate('window.scrollTo(0, document.body.scrollHeight)')
      page.wait_for_timeout(1000)

      # Strategy 4: Scroll timeline container to bottom
      begin
        page.evaluate(<<~JS)
          const timeline = document.querySelector('.timeline-load-wrap');
          if (timeline) {
            timeline.scrollTop = timeline.scrollHeight;
          }
        JS
        page.wait_for_timeout(1000)
      rescue
        # Ignore errors
      end

      # Strategy 5: Use keyboard to force loading
      if i % 20 == 0
        begin
          page.keyboard.press('End')
          page.wait_for_timeout(1000)
          page.keyboard.press('PageDown')
          page.wait_for_timeout(1000)
        rescue
          # Ignore keyboard errors
        end
      end

      # Stop if we've been stable for a very long time AND we have a reasonable number
      if count == last_count && i > 50 && count > 100
        stable_count = i - (last_count > 0 ? 1 : 0)
        if stable_count > 100  # Much longer stability period
          puts "   ⏹️ Stopping after #{stable_count} stable iterations"
          break
        end
      end
    end

    final_count = page.locator('.timeline-item').count
    puts "\n🎉 FINAL TIMELINE LOAD RESULT:"
    puts "   Total items loaded: #{final_count}"
    puts "   Total iterations: #{total_iterations}"
    puts "   Expected items: ~184"

    if final_count < 100
      puts "   ⚠️ WARNING: Only loaded #{final_count} items, expected ~184!"
      puts "   🔍 Let me check for alternative selectors..."

      # Check if there are other possible timeline selectors
      alternative_selectors = [
        '.timeline-item',
        '[data-timeline-id]',
        '[data-timeline-type]',
        '.lead-timeline-item',
        '.timeline-entry',
        '.activity-item'
      ]

      alternative_selectors.each do |selector|
        alt_count = page.locator(selector).count
        puts "   📊 #{selector}: #{alt_count} items"
      end
    end

    # Now check for Types 124 & 37 specifically
    puts "\n🎯 CHECKING FOR TYPES 124 & 37..."

    types_found = page.evaluate(<<~JS)
      (() => {
        const items = document.querySelectorAll('[data-timeline-type]');
        const typeCounts = {};
        const types124_37 = [];

        for (let item of items) {
          const typeCode = parseInt(item.getAttribute('data-timeline-type') || '0', 10);
          typeCounts[typeCode] = (typeCounts[typeCode] || 0) + 1;

          if (typeCode === 124 || typeCode === 37) {
            const contentEl = item.querySelector('.timeline-content');
            types124_37.push({
              type: typeCode,
              id: item.getAttribute('data-timeline-id'),
              hasContent: !!contentEl,
              contentLength: contentEl ? contentEl.innerText.length : 0,
              rawHTML: item.outerHTML.substring(0, 300)
            });
          }
        }

        return {
          allTypeCounts: typeCounts,
          types124_37: types124_37
        };
      })();
    JS

    puts "📊 TYPE CODE DISTRIBUTION:"
    types_found['allTypeCounts'].sort.each do |type, count|
      puts "   Type #{type}: #{count} events"
    end

    puts "\n🎯 TYPES 124 & 37 ANALYSIS:"
    if types_found['types124_37'].empty?
      puts "   ❌ NO Types 124 or 37 found in DOM!"
    else
      types_found['types124_37'].each do |item|
        puts "   📧 Type #{item['type']} (ID: #{item['id']})"
        puts "      Has content element: #{item['hasContent']}"
        puts "      Content length: #{item['contentLength']}"
        puts "      HTML preview: #{item['rawHTML']}"
      end
    end

    puts "\n" + "=" * 60
    puts "AGGRESSIVE TIMELINE LOAD COMPLETE!"

    browser.close
  end

rescue StandardError => e
  puts "❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end