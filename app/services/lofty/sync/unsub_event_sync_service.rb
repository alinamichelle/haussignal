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

        # Scrape ALL timeline events (need emails to match unsubs)
        all_entries = Lofty::Scrapers::TimelineScraper.new.scrape_all_for_lead(lofty_lead_id)
        
        stats = { 
          new: 0, 
          updated: 0, 
          skipped: 0,
          missing_email: 0,
          missing_subject: 0
        }

        # Filter for unsub events
        unsub_entries = all_entries.select { |e| e.type_code == 113 }
        
        Rails.logger.info "📊 Found #{all_entries.length} total events, #{unsub_entries.length} unsubs"

        unsub_entries.each do |unsub_entry|
          # Parse timestamp
          occurred_at = parse_timestamp(unsub_entry.timestamp_text)
          
          # Extract category from raw text
          category = extract_unsub_category(unsub_entry.raw_text)

          # Find the preceding email event
          email_entry = find_preceding_email(all_entries, unsub_entry)
          
          metadata = { unsub_category: category }
          
          if email_entry
            metadata[:unsubbedFromSubject] = extract_subject(email_entry.raw_text)
            metadata[:unsubbedFromSentAt] = parse_timestamp(email_entry.timestamp_text).to_s
            metadata[:unsubbedFromType] = type_code_to_name(email_entry.type_code)
            
            if metadata[:unsubbedFromSubject].blank?
              Rails.logger.warn "⚠️  No subject parsed for email before unsub timeline_id=#{unsub_entry.event_id}"
              stats[:missing_subject] += 1
            end
          else
            Rails.logger.warn "⚠️  No preceding email found for unsub timeline_id=#{unsub_entry.event_id} lead=#{lofty_lead_id}"
            stats[:missing_email] += 1
          end

          # Find or create event
          event = Event.find_or_initialize_by(lofty_timeline_id: unsub_entry.event_id)

          if event.new_record?
            event.assign_attributes(
              lead: lead,
              org_id: ENV.fetch('ORG_ID', 'realty-haus'),
              source: 'lofty',
              type_code: unsub_entry.type_code,
              event_type: :unsub,
              occurred_at: occurred_at,
              raw_text: unsub_entry.raw_text,
              metadata: metadata
            )
            event.save!
            stats[:new] += 1
            Rails.logger.info "  ✅ Created unsub: #{unsub_entry.event_id} - #{category} - Subject: #{metadata[:unsubbedFromSubject]&.[](0..50)}"
          else
            stats[:skipped] += 1
          end
        end

        Rails.logger.info "📊 Sync complete: #{stats[:new]} new, #{stats[:updated]} updated, #{stats[:skipped]} skipped"
        Rails.logger.info "⚠️  Missing data: #{stats[:missing_email]} no email match, #{stats[:missing_subject]} no subject"
        
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

      def find_preceding_email(all_entries, unsub_entry)
        # Find the most recent email event (type 103 or 105) that occurred before the unsub
        # Assuming entries are in chronological order (newest first)
        unsub_index = all_entries.index { |e| e.event_id == unsub_entry.event_id }
        return nil unless unsub_index
        
        # Look backward through timeline for an email
        all_entries[(unsub_index + 1)..-1]&.find do |entry|
          [103, 105].include?(entry.type_code)
        end
      end

      def extract_subject(email_raw_text)
        # Try to extract subject from email timeline entry
        # Common patterns:
        # "Subject: Foo Bar" or "Re: Foo Bar" or just the subject line
        return nil if email_raw_text.blank?
        
        # Look for "Subject:" pattern
        if email_raw_text =~ /Subject:\s*(.+?)$/i
          return $1.strip
        end
        
        # Look for "Re:" or "Fwd:" patterns
        if email_raw_text =~ /(Re:|Fwd:)\s*(.+?)$/i
          return email_raw_text[/^.+$/]&.strip
        end
        
        # Otherwise take first line as subject
        email_raw_text.lines.first&.strip
      end

      def type_code_to_name(type_code)
        case type_code
        when 103, 105 then 'email'
        when 113 then 'unsub'
        else 'unknown'
        end
      end

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
