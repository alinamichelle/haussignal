module Lofty
  module Sync
    class TimelineSyncService
      def initialize
        @scraper = Lofty::Scrapers::TimelineScraper.new
      end

      # Main sync method with incremental support
      def sync_for_lead(lofty_lead_id, incremental: true)
        Rails.logger.info "🔄 Syncing ALL activities for lead: #{lofty_lead_id} (incremental: #{incremental})"

        # Ensure lead exists
        lead = Lead.find_or_create_by!(lofty_lead_id: lofty_lead_id) do |l|
          l.org_id = ENV.fetch('ORG_ID', 'realty-haus')
        end

        # Determine if we need full or incremental sync
        last_synced_at = nil
        if incremental
          last_event = Event.where(lead: lead).order(occurred_at: :desc).first
          last_synced_at = last_event&.occurred_at
          
          if last_synced_at
            Rails.logger.info "  📅 Last activity: #{last_synced_at.strftime('%Y-%m-%d %H:%M:%S')} - will only sync newer activities"
          else
            Rails.logger.info "  📅 No existing activities found - performing full sync"
          end
        end

        # Scrape ALL timeline events
        all_entries = @scraper.scrape_all_for_lead(lofty_lead_id)
        
        Rails.logger.info "  📊 Scraped #{all_entries.length} timeline entries"

        # Filter by timestamp if incremental
        if incremental && last_synced_at
          before_count = all_entries.length
          all_entries = all_entries.select do |entry|
            entry_time = parse_timestamp(entry.timestamp_text)
            entry_time > last_synced_at
          end
          
          Rails.logger.info "  🔍 #{all_entries.length} new entries (filtered out #{before_count - all_entries.length} existing)"
          
          # If no new entries, skip processing
          if all_entries.empty?
            Rails.logger.info "  ✅ No new activities - skipping"
            lead.update_column(:timeline_synced_at, Time.current)
            return { new: 0, skipped: 0, already_synced: true }
          end
        end

        stats = { 
          email_sent: 0,
          email_opened: 0,
          sms: 0,
          call: 0,
          note: 0,
          smartplan: 0,
          alert_view: 0,
          unsub: 0,
          manual_unsub: 0,
          other: 0,
          skipped: 0,
          errors: 0
        }

        all_entries.each do |entry|
          process_activity(lead, entry, stats)
        end

        # Update last synced timestamp
        lead.update_column(:timeline_synced_at, Time.current)

        Rails.logger.info "  ✅ Sync complete: #{stats.except(:skipped, :errors).values.sum} new, #{stats[:skipped]} skipped, #{stats[:errors]} errors"
        log_stats_breakdown(stats)
        
        stats
      end

      # Batch sync for multiple leads
      def sync_for_multiple_leads(lofty_lead_ids, incremental: true)
        Rails.logger.info "🔄 Syncing ALL activities for #{lofty_lead_ids.length} leads (incremental: #{incremental})"
        
        # Skip list for problematic leads that cause infinite loops
        SKIP_LEADS = ['1139313628539303']
        
        total_stats = { 
          email_sent: 0, email_opened: 0, sms: 0, call: 0, 
          note: 0, smartplan: 0, alert_view: 0, unsub: 0, 
          manual_unsub: 0, other: 0, skipped: 0, errors: 0,
          leads_synced: 0, leads_failed: 0
        }

        lofty_lead_ids.each_with_index do |lofty_lead_id, index|
          # Skip problematic leads
          if SKIP_LEADS.include?(lofty_lead_id.to_s)
            Rails.logger.warn "\n⚠️  [#{index + 1}/#{lofty_lead_ids.length}] Skipping problematic lead: #{lofty_lead_id}"
            total_stats[:leads_failed] += 1
            next
          end
          begin
            Rails.logger.info "\n📍 [#{index + 1}/#{lofty_lead_ids.length}] Processing lead: #{lofty_lead_id}"
            
            stats = sync_for_lead(lofty_lead_id, incremental: incremental)
            
            # Aggregate stats
            stats.each do |key, value|
              total_stats[key] += value if total_stats.key?(key)
            end
            total_stats[:leads_synced] += 1
            
          rescue => e
            Rails.logger.error "  ❌ Failed to sync lead #{lofty_lead_id}: #{e.message}"
            Rails.logger.error "     #{e.backtrace.first(3).join("\n     ")}"
            total_stats[:leads_failed] += 1
          end
          
          # Progress indicator every 50 leads
          if (index + 1) % 50 == 0
            Rails.logger.info "\n📊 Progress: #{index + 1}/#{lofty_lead_ids.length} leads processed"
            log_stats_breakdown(total_stats)
          end
        end

        Rails.logger.info "\n🎉 Batch sync complete!"
        Rails.logger.info "   Leads: #{total_stats[:leads_synced]} synced, #{total_stats[:leads_failed]} failed"
        log_stats_breakdown(total_stats)
        
        total_stats
      end

      private

      def process_activity(lead, entry, stats)
        # Check if this activity already exists
        # Case 1: event has ID → dedupe by ID
        if entry.event_id.present?
          existing = Event.find_by(lofty_timeline_id: entry.event_id)
        else
          # Case 2: no ID → dedupe by text + timestamp + lead
          timestamp = parse_timestamp(entry.timestamp_text)
          existing = Event.find_by(
            lead_id: lead.id,
            raw_text: entry.raw_text,
            occurred_at: timestamp
          )
        end
        
        if existing
          stats[:skipped] += 1
          return
        end

        # Parse the entry using TimelineParser
        attrs = Lofty::TimelineParser.parse(entry, lead: lead)
        
        # Parser now NEVER returns nil - all events are captured
        
        # Create the event
        begin
          Event.create!(
            lofty_timeline_id: attrs[:lofty_timeline_id],
            lead: lead,
            org_id: ENV.fetch('ORG_ID', 'realty-haus'),
            source: 'lofty',
            type_code: attrs[:type_code],
            event_type: attrs[:event_type],
            occurred_at: attrs[:occurred_at],
            raw_text: attrs[:raw_text],
            metadata: attrs[:metadata],
            agent_id: attrs[:agent_id],
            email_category: attrs[:email_category],
            from_pipeline: attrs[:from_pipeline],
            to_pipeline: attrs[:to_pipeline],
            recording_available: attrs[:recording_available]
          )
          
          # Increment stat for this event type
          event_type = attrs[:event_type]
          stats[event_type] += 1 if stats.key?(event_type)
          
        rescue => e
          Rails.logger.error "  ❌ Failed to save event: #{e.message}"
          Rails.logger.error "     Timeline ID: #{attrs[:lofty_timeline_id]}, Type: #{attrs[:event_type]}"
          stats[:errors] += 1
        end
      end

      def parse_timestamp(timestamp_text)
        return Time.current if timestamp_text.blank?
        
        begin
          Time.zone.parse(timestamp_text)
        rescue
          Time.current
        end
      end

      def log_stats_breakdown(stats)
        breakdown = stats.except(:skipped, :errors, :leads_synced, :leads_failed)
                        .select { |_, count| count > 0 }
                        .map { |type, count| "#{type}: #{count}" }
                        .join(', ')
        
        Rails.logger.info "     #{breakdown}" if breakdown.present?
      end
    end
  end
end
