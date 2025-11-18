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

          context = browser.new_context(storage_state: @storage_state_path.to_s)
          page    = context.new_page

          url = "#{ENV['LOFTY_BASE_URL']}/admin/home/detail?leadId=#{lofty_lead_id}"
          Rails.logger.info "🔵 Scraping: #{url}"
          
          page.goto(url, wait_until: 'networkidle')
          page.wait_for_timeout(3000)

          # Auto-scroll to load all timeline items
          auto_scroll(page)

          # Extract all timeline items
          items = page.eval_on_selector_all(
            @selectors['timeline_item'],
            <<~JS
              elements => elements.map(el => ({
                eventId: el.getAttribute('#{@selectors['timeline_id_attr']}'),
                typeCode: parseInt(el.getAttribute('#{@selectors['timeline_type_attr']}') || '0', 10),
                timestampText: (el.querySelector('#{@selectors['timestamp']}') || {}).innerText || '',
                rawText: (el.querySelector('#{@selectors['content']}') || {}).innerText || '',
                audioUrl: el.querySelector('#{@selectors['audio']}') ? el.querySelector('#{@selectors['audio']}').getAttribute('src') : null
              }))
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
              audio_url: item['audioUrl']
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

          context = browser.new_context(storage_state: @storage_state_path.to_s)
          page    = context.new_page

          url = "#{ENV['LOFTY_BASE_URL']}/admin/home/detail?leadId=#{lofty_lead_id}"
          Rails.logger.info "🔵 Scraping: #{url}"
          
          page.goto(url, wait_until: 'networkidle')
          page.wait_for_timeout(3000)

          # Auto-scroll to load all timeline items
          auto_scroll(page)

          # Extract all timeline items
          items = page.eval_on_selector_all(
            @selectors['timeline_item'],
            <<~JS
              elements => elements.map(el => ({
                eventId: el.getAttribute('#{@selectors['timeline_id_attr']}'),
                typeCode: parseInt(el.getAttribute('#{@selectors['timeline_type_attr']}') || '0', 10),
                timestampText: (el.querySelector('#{@selectors['timestamp']}') || {}).innerText || '',
                rawText: (el.querySelector('#{@selectors['content']}') || {}).innerText || '',
                audioUrl: el.querySelector('#{@selectors['audio']}') ? el.querySelector('#{@selectors['audio']}').getAttribute('src') : null
              }))
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
              audio_url: item['audioUrl']
            )
          end

          browser.close
        end

        entries
      end

      private

      def auto_scroll(page)
        Rails.logger.info "📜 Auto-scrolling to load all timeline items..."
        
        20.times do
          page.evaluate('window.scrollTo(0, document.body.scrollHeight)')
          page.wait_for_timeout(1000)
        end
        
        Rails.logger.info "✅ Scrolling complete"
      end
    end
  end
end
