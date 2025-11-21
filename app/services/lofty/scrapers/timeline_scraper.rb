require 'playwright'

module Lofty
  module Scrapers
    class TimelineScraper
      def initialize
        @storage_state_path = Rails.root.join('tmp/lofty_storage_state.json')
        @selectors = YAML.load_file(Rails.root.join('config/lofty_selectors.yml'))
      end

      # Scrape unsub events only (Phase 0)
      def scrape_unsubs_for_lead(lofty_lead_id)
        entries = []

        Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
          browser = playwright.chromium.launch(headless: true)
          
          unless File.exist?(@storage_state_path)
            raise "Session state not found! Run: bin/rails lofty:login"
          end

          context = browser.new_context(storageState: @storage_state_path.to_s)
          page    = context.new_page

          url = "#{ENV['LOFTY_BASE_URL']}/admin/home/detail?leadId=#{lofty_lead_id}"
          Rails.logger.info "🔵 Scraping: #{url}"
          
          page.goto(url, waitUntil: 'networkidle')
          page.wait_for_timeout(3000)

          # Auto-scroll to load all timeline items
          auto_scroll(page)

          # Extract all timeline items with full metadata
          items = page.eval_on_selector_all(
            @selectors['timeline_item'],
            <<~JS
              elements => elements.map(el => {
                // Extract all data-* attributes
                const dataAttributes = {};
                Array.from(el.attributes).forEach(attr => {
                  if (attr.name.startsWith('data-')) {
                    dataAttributes[attr.name.replace('data-', '')] = attr.value;
                  }
                });
                
                // Extract CSS classes
                const cssClasses = Array.from(el.classList);
                
                // Get HTML content for detailed parsing
                const contentEl = el.querySelector('#{@selectors['content']}');
                const htmlContent = contentEl ? contentEl.innerHTML : '';
                
                // Extract all possible email metadata from data attributes
                const emailId = el.getAttribute('data-email-id') || 
                               el.getAttribute('data-emailid') ||
                               el.getAttribute('data-message-id') || '';
                               
                const emailSubject = el.getAttribute('data-email-subject') ||
                                    el.getAttribute('data-subject') || '';
                                    
                const emailType = el.getAttribute('data-email-type') ||
                                 el.getAttribute('data-type') || '';
                
                return {
                  eventId: el.getAttribute('#{@selectors['timeline_id_attr']}'),
                  typeCode: parseInt(el.getAttribute('#{@selectors['timeline_type_attr']}') || '0', 10),
                  timestampText: (el.querySelector('#{@selectors['timestamp']}') || {}).innerText || '',
                  rawText: (el.querySelector('#{@selectors['content']}') || {}).innerText || '',
                  audioUrl: el.querySelector('#{@selectors['audio']}') ? el.querySelector('#{@selectors['audio']}').getAttribute('src') : null,
                  htmlContent: htmlContent,
                  dataAttributes: dataAttributes,
                  cssClasses: cssClasses,
                  emailId: emailId,
                  emailSubject: emailSubject,
                  emailType: emailType
                };
              })
            JS
          )

          Rails.logger.info "📊 Found #{items.length} total timeline items"

          # Filter for unsub events (type_code 113)
          items.each do |item|
            next unless item['typeCode'] == 113

            entries << RawTimelineEntry.new(
              lead_lofty_id: lofty_lead_id,
              event_id: item['eventId'],
              type_code: item['typeCode'],
              timestamp_text: item['timestampText'],
              raw_text: item['rawText'],
              audio_url: item['audioUrl'],
              html_content: item['htmlContent'],
              data_attributes: item['dataAttributes'],
              css_classes: item['cssClasses']
            )
          end

          Rails.logger.info "✅ Found #{entries.length} unsub events"

          browser.close
        end

        entries
      end

      # HYBRID SCRAPER: API for first 20 (rich content) + DOM for rest (full history)
      def scrape_all_for_lead(lofty_lead_id)
        entries = []
        api_event_ids = Set.new

        Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
          browser = playwright.chromium.launch(headless: true)
          
          unless File.exist?(@storage_state_path)
            raise "Session state not found! Run: bin/rails lofty:login"
          end

          context = browser.new_context(storageState: @storage_state_path.to_s)
          page    = context.new_page

          url = "#{ENV['LOFTY_BASE_URL']}/admin/home/detail?leadId=#{lofty_lead_id}"
          Rails.logger.info "🔵 HYBRID scraping for lead: #{lofty_lead_id}"
          
          # STEP 1: Get first 20 events from API (rich content with full note bodies)
          puts "\n🌐 STEP 1: Fetching first 20 events via API (full note bodies)..."
          api_timelines = fetch_first_page_json(page, lofty_lead_id, url)
          puts "   ✅ API captured: #{api_timelines.length} events with rich content"
          
          api_timelines.each do |item|
            event_id = item['id'].to_s
            api_event_ids << event_id
            
            entries << RawTimelineEntry.new(
              lead_lofty_id: lofty_lead_id,
              event_id: event_id,
              type_code: item['timelineType'],
              timestamp_text: nil,
              raw_text: nil,
              audio_url: nil,
              html_content: nil,
              data_attributes: {},
              css_classes: [],
              raw_json: item  # Full JSON for rich parsing
            )
          end
          
          # STEP 2: Get ALL events from DOM (full history)
          puts "\n📜 STEP 2: Loading full timeline via DOM scroll (all history)..."
          load_full_email_timeline(page)
          
          # Extract DOM events
          items = page.eval_on_selector_all(
            @selectors['timeline_item'],
            <<~JS
              elements => elements.map(el => {
                const dataAttributes = {};
                Array.from(el.attributes).forEach(attr => {
                  if (attr.name.startsWith('data-')) {
                    dataAttributes[attr.name.replace('data-', '')] = attr.value;
                  }
                });
                
                const cssClasses = Array.from(el.classList);
                const contentEl = el.querySelector('#{@selectors['content']}');
                const htmlContent = contentEl ? contentEl.innerHTML : '';
                
                return {
                  eventId: el.getAttribute('#{@selectors['timeline_id_attr']}'),
                  typeCode: parseInt(el.getAttribute('#{@selectors['timeline_type_attr']}') || '0', 10),
                  timestampText: (el.querySelector('#{@selectors['timestamp']}') || {}).innerText || '',
                  rawText: (el.querySelector('#{@selectors['content']}') || {}).innerText || '',
                  audioUrl: el.querySelector('#{@selectors['audio']}') ? el.querySelector('#{@selectors['audio']}').getAttribute('src') : null,
                  htmlContent: htmlContent,
                  dataAttributes: dataAttributes,
                  cssClasses: cssClasses
                };
              })
            JS
          )
          
          puts "   📊 DOM extracted: #{items.length} total events"
          
          # Add DOM events that weren't already captured by API
          dom_added = 0
          items.each do |item|
            event_id = item['eventId']
            next if api_event_ids.include?(event_id)  # Skip duplicates
            
            entries << RawTimelineEntry.new(
              lead_lofty_id: lofty_lead_id,
              event_id: event_id,
              type_code: item['typeCode'],
              timestamp_text: item['timestampText'],
              raw_text: item['rawText'],
              audio_url: item['audioUrl'],
              html_content: item['htmlContent'],
              data_attributes: item['dataAttributes'],
              css_classes: item['cssClasses'],
              raw_json: nil  # DOM events don't have JSON
            )
            dom_added += 1
          end
          
          puts "   ✅ Added #{dom_added} older events from DOM"
          puts "\n🎉 HYBRID TOTAL: #{entries.length} events (#{api_timelines.length} API + #{dom_added} DOM)"

          browser.close
        end

        entries
      end
      
      # Fetch first page from API (20 events with rich content)
      def fetch_first_page_json(page, lead_id, url)
        captured_responses = []
        
        # Set up response listener BEFORE navigation
        page.on('response', ->(response) do
          if response.request.method == 'GET' &&
             response.url.include?('/lead-timeline-server/timeline/lead/all/filtered') &&
             response.url.include?("leadId=#{lead_id}")
            captured_responses << response
          end
        end)
        
        # Navigate to page (this triggers first API call)
        page.goto(url, waitUntil: 'networkidle')
        page.wait_for_timeout(2000)
        
        # Return first page only
        if captured_responses.any?
          response = captured_responses.first
          json = JSON.parse(response.body)
          data = json['data'] || {}
          data['timeLines'] || []
        else
          []
        end
      end

      private
      
      # =========================================
      # FULL TIMELINE LOADER FOR LOFTY
      # - Scrolls the timeline container
      # - Scrolls the page body
      # - Clicks "Click to view..." button if present
      # - Stops when item count stops increasing
      # =========================================
      
      ITEM_SELECTOR = '.timeline-item'
      
      def load_full_email_timeline(page)
        puts "🧵 Starting full timeline load..."
        
        # 1) Make sure the container exists
        page.wait_for_selector('.timeline-load-wrap', timeout: 15_000)
        container = page.locator('.timeline-load-wrap')
        puts "✅ Timeline container found"
        page.wait_for_timeout(2000)
        
        items = page.locator(ITEM_SELECTOR)
        
        last_count = 0
        stable_iterations = 0
        max_stable = 15  # "no new items" loops before we give up
        
        1.upto(200) do |i|
          count = items.count
          
          if count > last_count
            puts "   [#{i}] 📥 +#{count - last_count} new items (total: #{count})"
            last_count = count
            stable_iterations = 0
          else
            stable_iterations += 1
            puts "   [#{i}] stable #{stable_iterations}/#{max_stable}, items=#{count}" if i % 5 == 0
          end
          
          # Stop once we've been stable for a while
          break if stable_iterations >= max_stable
          
          # 2) Scroll: move the LAST item into view – this is the key
          if count > 0
            items.nth(count - 1).scroll_into_view_if_needed
          else
            container.scroll_into_view_if_needed
          end
          
          page.wait_for_timeout(600)
          
          # 3) If the load-more button is actually visible, click it
          begin
            btn = page.locator('.new-timeline-bottom-btn, .timeline-bottom-btn')
            if btn.count > 0 && btn.first.visible?
              puts "   🔽 Clicked load-more button..."
              btn.first.click
              page.wait_for_timeout(2000)
              stable_iterations = 0
            end
          rescue => e
            puts "   ⚠️  Button click error: #{e.message}"
          end
        end
        
        final = items.count
        visible = page.evaluate(<<~JS)
          (() => {
            return Array.from(document.querySelectorAll('.timeline-item')).filter(el => el.offsetParent !== null).length;
          })();
        JS
        
        puts "🎉 Final timeline item count: #{final}"
        puts "🔍 Debug: DOM items=#{final}, visible=#{visible}"
      end
      
      # Legacy method - calls new system
      def auto_scroll(page)
        load_full_email_timeline(page)
      end
      
      # Expand all collapsed timeline content (notes, call details, etc.)
      def expand_all_timeline_content(page)
        Rails.logger.info "🔍 Expanding collapsed timeline content..."
        
        # First, try clicking on each timeline item to expand it
        begin
          timeline_items = page.locator('.timeline-item')
          count = timeline_items.count
          Rails.logger.info "  Clicking on #{count} timeline items to expand..."
          
          count.times do |i|
            begin
              # Click on the timeline-main or timeline-content area
              item = timeline_items.nth(i)
              main = item.locator('.timeline-main, .timeline-content').first
              if main
                main.click(timeout: 500, force: true)
                page.wait_for_timeout(100)
              end
            rescue => e
              # Item might not be clickable, continue
            end
          end
          
          page.wait_for_timeout(500)
        rescue => e
          Rails.logger.warn "  ⚠️ Error clicking timeline items: #{e.message}"
        end
        
        # Then click all "View more", "Show more", "View details" buttons
        expand_selectors = [
          '.timeline-main .more-text',
          '.timeline-content .more-text',
          '.timeline-title .more-text',
          '.show-more',
          '.view-more',
          '.view-detail',
          '.expand-button',
          'button:has-text("View more")',
          'button:has-text("Show more")',
          'button:has-text("View Details")',
          'span:has-text("More")',
          'span:has-text("Less")',
          'a:has-text("More")',
          '.timeline-item [class*="more"]',
          '.timeline-item [class*="expand"]'
        ]
        
        expand_selectors.each do |selector|
          begin
            buttons = page.locator(selector)
            count = buttons.count
            
            if count > 0
              Rails.logger.info "  Found #{count} '#{selector}' elements, clicking..."
              count.times do |i|
                begin
                  buttons.nth(i).click(timeout: 1000, force: true)
                  page.wait_for_timeout(150)
                rescue => e
                  # Button might not be clickable, skip it
                end
              end
            end
          rescue => e
            # Selector might not exist, continue
          end
        end
        
        Rails.logger.info "✅ Finished expanding content"
        page.wait_for_timeout(1000)
      end
    end
  end
end
