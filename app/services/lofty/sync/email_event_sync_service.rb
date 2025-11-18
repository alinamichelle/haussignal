module Lofty
  module Sync
    class EmailEventSyncService
      def initialize
        @scraper = Lofty::Scrapers::TimelineScraper.new
        @classifier = Lofty::EmailClassifier
      end

      def sync_for_lead(lofty_lead_id)
        Rails.logger.info "🔄 Syncing email events for lead: #{lofty_lead_id}"

        # Ensure lead exists
        lead = Lead.find_or_create_by!(lofty_lead_id: lofty_lead_id) do |l|
          l.org_id = ENV.fetch('ORG_ID', 'realty-haus')
        end

        # Scrape all timeline events
        all_entries = @scraper.scrape_all_for_lead(lofty_lead_id)
        
        stats = { 
          email_sent: 0,
          email_opened: 0,
          skipped: 0
        }

        all_entries.each do |entry|
          # Process email sent events
          if @classifier.is_email_sent?(entry.type_code)
            process_email_sent(lead, entry, stats)
          end
          
          # Process email opened events (type 37 - alert opens)
          if entry.type_code == 37 # Alert email opened
            process_email_opened(lead, entry, stats)
          end
        end

        Rails.logger.info "📊 Email sync complete: #{stats[:email_sent]} sent, #{stats[:email_opened]} opened, #{stats[:skipped]} skipped"
        
        stats
      end

      private

      def process_email_sent(lead, entry, stats)
        occurred_at = parse_timestamp(entry.timestamp_text)
        
        email_type = @classifier.classify_email_type(entry)
        email_subject = @classifier.extract_email_subject(entry)
        email_header = @classifier.extract_email_header(entry)
        email_id = @classifier.extract_email_id(entry)
        template_name = @classifier.extract_template_name(entry)

        metadata = {
          emailType: email_type,
          emailSubject: email_subject,
          emailHeader: email_header,
          emailId: email_id,
          templateName: template_name,
          rawText: entry.raw_text
        }

        event = Event.find_or_initialize_by(lofty_timeline_id: entry.event_id)

        if event.new_record?
          event.assign_attributes(
            lead: lead,
            org_id: ENV.fetch('ORG_ID', 'realty-haus'),
            source: 'lofty',
            type_code: entry.type_code,
            event_type: :email_sent,
            occurred_at: occurred_at,
            raw_text: entry.raw_text,
            metadata: metadata
          )
          event.save!
          stats[:email_sent] += 1
        else
          stats[:skipped] += 1
        end
      end

      def process_email_opened(lead, entry, stats)
        occurred_at = parse_timestamp(entry.timestamp_text)
        
        email_subject = @classifier.extract_email_subject(entry)
        
        metadata = {
          emailSubject: email_subject,
          rawText: entry.raw_text
        }

        event = Event.find_or_initialize_by(lofty_timeline_id: entry.event_id)

        if event.new_record?
          event.assign_attributes(
            lead: lead,
            org_id: ENV.fetch('ORG_ID', 'realty-haus'),
            source: 'lofty',
            type_code: entry.type_code,
            event_type: :email_opened,
            occurred_at: occurred_at,
            raw_text: entry.raw_text,
            metadata: metadata
          )
          event.save!
          stats[:email_opened] += 1
        else
          stats[:skipped] += 1
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
    end
  end
end
