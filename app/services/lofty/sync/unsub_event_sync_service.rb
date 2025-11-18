module Lofty
  module Sync
    class UnsubEventSyncService
      def initialize
        @scraper = Lofty::Scrapers::TimelineScraper.new
      end

      def sync_for_lead(lofty_lead_id)
        Rails.logger.info "🔄 Syncing unsub events for lead: #{lofty_lead_id}"

        # Ensure lead exists (create stub if needed)
        lead = Lead.find_or_create_by!(lofty_lead_id: lofty_lead_id) do |l|
          l.org_id = ENV.fetch('ORG_ID', 'realty-haus')
        end

        # Scrape unsub events
        raw_entries = @scraper.scrape_unsubs_for_lead(lofty_lead_id)
        
        stats = { new: 0, updated: 0, skipped: 0 }

        raw_entries.each do |entry|
          # Parse timestamp
          occurred_at = parse_timestamp(entry.timestamp_text)
          
          # Extract category from raw text
          category = extract_unsub_category(entry.raw_text)

          # Find or create event
          event = Event.find_or_initialize_by(lofty_timeline_id: entry.event_id)

          if event.new_record?
            event.assign_attributes(
              lead: lead,
              org_id: ENV.fetch('ORG_ID', 'realty-haus'),
              source: 'lofty',
              type_code: entry.type_code,
              event_type: :unsub,
              occurred_at: occurred_at,
              raw_text: entry.raw_text,
              metadata: { unsub_category: category }
            )
            event.save!
            stats[:new] += 1
            Rails.logger.info "  ✅ Created unsub event: #{entry.event_id} - #{category}"
          else
            stats[:skipped] += 1
          end
        end

        Rails.logger.info "📊 Sync complete: #{stats[:new]} new, #{stats[:updated]} updated, #{stats[:skipped]} skipped"
        
        stats
      end

      def sync_for_multiple_leads(lofty_lead_ids)
        Rails.logger.info "🔄 Syncing unsub events for #{lofty_lead_ids.length} leads"
        
        total_stats = { new: 0, updated: 0, skipped: 0 }

        lofty_lead_ids.each do |lofty_lead_id|
          begin
            stats = sync_for_lead(lofty_lead_id)
            total_stats[:new] += stats[:new]
            total_stats[:updated] += stats[:updated]
            total_stats[:skipped] += stats[:skipped]
          rescue => e
            Rails.logger.error "❌ Failed to sync lead #{lofty_lead_id}: #{e.message}"
          end
        end

        Rails.logger.info "🎉 Total sync complete: #{total_stats[:new]} new, #{total_stats[:updated]} updated, #{total_stats[:skipped]} skipped"
        
        total_stats
      end

      private

      def parse_timestamp(timestamp_text)
        # Handle various Lofty timestamp formats
        # Examples: "2 hours ago", "Yesterday at 3:45 PM", "Jan 15 at 10:30 AM"
        
        return Time.current if timestamp_text.blank?

        # Try to parse with Chronic or similar gem in the future
        # For now, return current time as fallback
        begin
          Time.zone.parse(timestamp_text)
        rescue
          Time.current
        end
      end

      def extract_unsub_category(raw_text)
        return 'unknown' if raw_text.blank?

        text_lower = raw_text.downcase

        case text_lower
        when /seller report/
          'seller_reports'
        when /home report/
          'home_reports'
        when /market alert/
          'market_alerts'
        when /listing alert/
          'listing_alerts'
        when /newsletter/
          'newsletter'
        when /email/
          'all_emails'
        else
          'unknown'
        end
      end
    end
  end
end
