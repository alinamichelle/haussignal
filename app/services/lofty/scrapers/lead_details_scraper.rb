require 'playwright'

module Lofty
  module Scrapers
    class LeadDetailsScraper
      def initialize
        @storage_state_path = Rails.root.join('tmp/lofty_storage_state.json')
      end

      def scrape_lead_details(lofty_lead_id)
        details = {
          lofty_lead_id: lofty_lead_id,
          pipeline: nil,
          segment: nil,
          family_members: [],
          referral_source: nil,
          reg_date: nil,
          tasks: []
        }

        Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
          browser = playwright.chromium.launch(headless: true)
          
          unless File.exist?(@storage_state_path)
            raise "Session state not found! Run: bin/rails lofty:login"
          end

          context = browser.new_context(storageState: @storage_state_path.to_s)
          page = context.new_page

          url = "#{ENV['LOFTY_BASE_URL']}/admin/home/detail?leadId=#{lofty_lead_id}"
          Rails.logger.info "🔵 Scraping lead details: #{url}"
          
          page.goto(url, waitUntil: 'load')
          page.wait_for_timeout(3000) # Give time for dynamic content to load

          # DEBUG: dump detail-info block to see exact labels
          begin
            detail_texts = page.locator('div.detail-info').all_inner_texts
            Rails.logger.info "[LeadDetailsScraper] detail-info raw text for #{lofty_lead_id}:\n#{detail_texts.join("\n---\n")}"
          rescue => e
            Rails.logger.warn "[LeadDetailsScraper] Could not dump detail-info for #{lofty_lead_id}: #{e.class} - #{e.message}"
          end

          # Extract pipeline
          details[:pipeline] = extract_pipeline(page)
          
          # Extract segment
          details[:segment] = extract_segment(page)
          
          # Extract referral source
          details[:referral_source] = extract_referral_source(page)
          
          # Extract reg date
          details[:reg_date] = extract_reg_date(page)
          
          # Extract family members
          details[:family_members] = extract_family_members(page)
          
          # Extract tasks
          details[:tasks] = extract_tasks(page)

          browser.close
        end

        details
      end

      private
      
      # Helper for dropdowns (Pipeline / Segment)
      def dropdown_value_by_label(page, label_text)
        item = page.locator(
          'div.detail-info .select-item',
          has: page.locator('span.select-label', hasText: label_text)
        )

        text_el = item.locator('span.com-dropdown-text, div.com-dropdown-label span:not(.icon2017)').first
        return nil if text_el.count == 0

        text_el.inner_text.strip
      rescue => e
        Rails.logger.warn "[LeadDetailsScraper] Failed dropdown '#{label_text}': #{e.class} - #{e.message}"
        nil
      end
      
      # Helper for detail rows (Source / Reg Date) - simple text extraction
      def detail_value_by_label(page, label_variants)
        label_variants = Array(label_variants)

        # Get all text from the Details sidebar
        details_text = page.evaluate(<<~JS)
          (() => {
            const detailsBox = document.querySelector('#lead-detail-box, .detail-box, [class*="detail"]');
            return detailsBox ? detailsBox.innerText : document.body.innerText;
          })()
        JS
        
        # Try each label variant
        label_variants.each do |label_text|
          # Match pattern: "Label: Value" or "Label:\nValue"
          regex = /#{Regexp.escape(label_text)}[:\s]*([^\n]+)/i
          if details_text =~ regex
            value = $1.strip
            return value if value.present? && value.length < 200
          end
        end

        Rails.logger.warn "[LeadDetailsScraper] No match found for labels=#{label_variants.inspect}"
        nil
      rescue => e
        Rails.logger.warn "[LeadDetailsScraper] Failed detail for labels=#{label_variants.inspect}: #{e.class} - #{e.message}"
        nil
      end

      def extract_pipeline(page)
        dropdown_value_by_label(page, 'Pipeline:')
      end

      def extract_segment(page)
        dropdown_value_by_label(page, 'Segment:')
      end

      def extract_referral_source(page)
        # Try a couple of variants just in case Lofty changes copy
        detail_value_by_label(page, ['Source:', 'Source'])
      end
      
      def extract_reg_date(page)
        # Handle "Reg Date", "Reg date", "Registration Date", etc.
        detail_value_by_label(page, ['Reg Date', 'Reg date', 'Registration Date', 'Reg. Date'])
      end

      def extract_family_members(page)
        family_members = []
        
        begin
          family_data = page.evaluate(<<~JS)
            (() => {
              const members = [];
              const detailsSection = document.querySelector('.detail-left, [class*="detail"]');
              if (!detailsSection) return members;
              
              const text = detailsSection.innerText;
              const match = text.match(/Family Members[:\s]*(\d+)/);
              
              if (match) {
                const count = parseInt(match[1]);
                // Look for family member names
                const lines = text.split('\n');
                const familyIdx = lines.findIndex(l => l.includes('Family Members'));
                if (familyIdx >= 0 && familyIdx + 1 < lines.length) {
                  // Get next few lines which might be names
                  for (let i = familyIdx + 1; i < Math.min(familyIdx + count + 2, lines.length); i++) {
                    const line = lines[i].trim();
                    if (line && !line.includes('Add Family') && line.length < 50) {
                      members.push(line);
                    }
                  }
                }
              }
              
              return members;
            })()
          JS
          
          family_members = family_data if family_data.is_a?(Array)
          Rails.logger.info "Found #{family_members.length} family members"
        rescue => e
          Rails.logger.warn "Could not extract family members: #{e.message}"
        end
        
        family_members
      end

      def extract_tasks(page)
        tasks = []
        
        begin
          tasks_data = page.evaluate(<<~JS)
            (() => {
              const tasks = [];
              
              // Find Tasks heading
              const tasksHeading = Array.from(document.querySelectorAll('*')).find(el => 
                el.innerText && el.innerText.trim() === 'Tasks' && 
                (el.classList.contains('title') || el.tagName === 'H2' || el.tagName === 'H3')
              );
              
              if (!tasksHeading) return tasks;
              
              // Get the content-box that contains task items
              const container = tasksHeading.closest('[class*="title-box"]')?.parentElement;
              if (!container) return tasks;
              
              const taskItems = container.querySelectorAll('.item-box');
              
              taskItems.forEach(taskEl => {
                const nameWrap = taskEl.querySelector('.name-wrap');
                const descEl = taskEl.querySelector('.desc, [class*="desc"]');
                const agentEl = taskEl.querySelector('.agent-name');
                const roleEl = taskEl.querySelector('.role-type');
                
                if (nameWrap) {
                  const taskName = nameWrap.querySelector('.name')?.innerText.trim() || '';
                  const taskText = taskEl.innerText;
                  
                  // Parse the description (bullets and links)
                  const descLines = [];
                  if (descEl) {
                    const desc = descEl.innerText;
                    descLines.push(desc);
                  } else {
                    // Extract from task text if no desc element
                    const lines = taskText.split('\n').filter(l => l.trim());
                    // Skip first line (name) and last line (agent info)
                    for (let i = 1; i < lines.length - 1; i++) {
                      if (lines[i].includes('http') || lines[i].startsWith('•')) {
                        descLines.push(lines[i].trim());
                      }
                    }
                  }
                  
                  tasks.push({
                    name: taskName,
                    description: descLines.join('\n'),
                    full_text: taskText.trim(),
                    agent: agentEl ? agentEl.innerText.trim() : '',
                    role: roleEl ? roleEl.innerText.trim() : ''
                  });
                }
              });
              
              return tasks;
            })()
          JS
          
          tasks = tasks_data if tasks_data.is_a?(Array)
          Rails.logger.info "Found #{tasks.length} tasks"
        rescue => e
          Rails.logger.warn "Could not extract tasks: #{e.message}"
        end
        
        tasks
      end
    end
  end
end
