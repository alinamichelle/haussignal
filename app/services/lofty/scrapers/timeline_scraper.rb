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

      # Scrape all timeline events (for Phase 1)
      def scrape_all_for_lead(lofty_lead_id)
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
          
          # Expand all collapsed content (notes, call details, etc.)
          expand_all_timeline_content(page)

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
                // Use entire timeline-item HTML to capture shadow-root-container
                const htmlContent = el.innerHTML || '';
                
                // Extract all possible email metadata from data attributes
                const emailId = el.getAttribute('data-email-id') || 
                               el.getAttribute('data-emailid') ||
                               el.getAttribute('data-message-id') || '';
                               
                const emailSubject = el.getAttribute('data-email-subject') ||
                                    el.getAttribute('data-subject') || '';
                                    
                const emailType = el.getAttribute('data-email-type') ||
                                 el.getAttribute('data-type') || '';
                
                // Get text from both content and main areas (some content is in timeline-main)
                const contentText = (el.querySelector('#{@selectors['content']}') || {}).innerText || '';
                const mainText = (el.querySelector('.timeline-main') || {}).innerText || '';
                const titleText = (el.querySelector('.timeline-title') || {}).innerText || '';
                
                // Check for shadow-root-container (Lofty has typo: "shawdow-root-container")
                const shadowText = (el.querySelector('.shawdow-root-container') || {}).innerText || '';
                const shadowText2 = (el.querySelector('.shadow-root-container') || {}).innerText || '';
                
                // Combine all text sources, preferring the longest
                let rawText = contentText;
                if (mainText.length > rawText.length) rawText = mainText;
                if (titleText.length > rawText.length) rawText = titleText;
                if (shadowText.length > rawText.length) rawText = shadowText;
                if (shadowText2.length > rawText.length) rawText = shadowText2;
                
                // Fallback: get all text from the element
                if (!rawText) rawText = el.innerText || '';
                
                return {
                  eventId: el.getAttribute('#{@selectors['timeline_id_attr']}'),
                  typeCode: parseInt(el.getAttribute('#{@selectors['timeline_type_attr']}') || '0', 10),
                  timestampText: (el.querySelector('#{@selectors['timestamp']}') || {}).innerText || '',
                  rawText: rawText,
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

          items.each do |item|
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

          browser.close
        end

        entries
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
