module Lofty
  module Sync
    class UnsubEventSyncService
      def initialize
        @scraper = Lofty::Scrapers::TimelineScraper.new
        @attributor = Lofty::UnsubAttributionService.new
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

        # Filter for unsub events (both automatic and manual)
        auto_unsub_entries = all_entries.select { |e| e.type_code == 113 }
        manual_unsub_entries = all_entries.select { |e| e.type_code == 111 }
        
        Rails.logger.info "📊 Found #{all_entries.length} total events, #{auto_unsub_entries.length} auto unsubs, #{manual_unsub_entries.length} manual unsubs"

        # Process automatic unsubs (type 113)
        auto_unsub_entries.each do |unsub_entry|
          # Parse timestamp
          occurred_at = parse_timestamp(unsub_entry.timestamp_text)
          
          # Extract category from raw text
          category = extract_unsub_category(unsub_entry.raw_text)

          # Build base metadata
          metadata = { 
            unsubCategory: category,
            leadBehavior: unsub_entry.raw_text
          }
          
          # Use attribution service to find trigger email and build full metadata
          attribution = @attributor.attribute_unsub(unsub_entry, all_entries)
          
          if attribution
            # Now match with actual opened events from the database
            trigger_sent_event = find_sent_event_by_subject(
              lead, 
              attribution[:emailSubject], 
              parse_timestamp(unsub_entry.timestamp_text)
            )
            
            if trigger_sent_event
              # Get all opened events for this lead
              opened_events = Event.where(lead: lead, event_type: :email_opened)
              
              # Use matcher to find the correct open
              matcher = Lofty::Matchers::EmailOpenMatcher.new(trigger_sent_event, opened_events)
              matched_open = matcher.call
              
              # Rebuild attribution with matched open
              if matched_open
                attribution[:openedAt] = matched_open.occurred_at.iso8601
                attribution[:openStatus] = 'opened'
                
                sent_at = trigger_sent_event.occurred_at
                unsub_at = parse_timestamp(unsub_entry.timestamp_text)
                
                attribution[:secondsFromSendToOpen] = (matched_open.occurred_at - sent_at).to_i
                attribution[:secondsFromOpenToUnsub] = (unsub_at - matched_open.occurred_at).to_i
                attribution[:secondsFromSendToUnsub] = (unsub_at - sent_at).to_i
                
                # Update context flags
                attribution[:unsubContext][:emailOpened] = true
                attribution[:unsubContext][:unsubWithoutOpening] = false
                
                if attribution[:secondsFromOpenToUnsub] < 300
                  attribution[:unsubContext][:quickUnsubAfterOpen] = true
                end
              end
            end
            
            metadata[:triggerEmail] = attribution
            
            if attribution[:emailSubject].blank?
              Rails.logger.warn "⚠️  No subject parsed for email before unsub timeline_id=#{unsub_entry.event_id}"
              stats[:missing_subject] += 1
            end
          else
            Rails.logger.warn "⚠️  No trigger email found for unsub timeline_id=#{unsub_entry.event_id} lead=#{lofty_lead_id}"
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
            
            # Log with full attribution details
            if attribution
              subject = attribution[:emailSubject] || '(no subject)'
              email_type = attribution[:emailType] || 'unknown'
              open_status = attribution[:openStatus] || 'unknown'
              time_info = if attribution[:secondsFromSendToUnsub]
                "#{(attribution[:secondsFromSendToUnsub] / 60.0).round(1)} min after send"
              else
                'unknown timing'
              end
              
              Rails.logger.info "  ✅ Created unsub: #{category} | #{email_type} | #{open_status} | #{time_info}"
              Rails.logger.info "     Subject: #{subject[0..70]}"
            else
              Rails.logger.info "  ✅ Created unsub: #{unsub_entry.event_id} - #{category} - (no email attribution)"
            end
          else
            stats[:skipped] += 1
          end
        end

        # Process manual unsubs (type 111)
        manual_unsub_entries.each do |unsub_entry|
          # Parse timestamp
          occurred_at = parse_timestamp(unsub_entry.timestamp_text)
          
          # Extract category and agent from raw text
          category = extract_manual_unsub_category(unsub_entry.raw_text)
          agent_name = extract_agent_name(unsub_entry.raw_text)
          
          # Build metadata for manual unsub (no trigger email attribution)
          metadata = { 
            unsubCategory: category,
            unsubType: 'manual',
            performedBy: agent_name,
            leadBehavior: unsub_entry.raw_text
          }
          
          # Find or create event
          event = Event.find_or_initialize_by(lofty_timeline_id: unsub_entry.event_id)

          if event.new_record?
            event.assign_attributes(
              lead: lead,
              org_id: ENV.fetch('ORG_ID', 'realty-haus'),
              source: 'lofty',
              type_code: unsub_entry.type_code,
              event_type: :manual_unsub,
              occurred_at: occurred_at,
              raw_text: unsub_entry.raw_text,
              metadata: metadata
            )
            event.save!
            stats[:new] += 1
            
            Rails.logger.info "  ✅ Created manual unsub: #{category} by #{agent_name}"
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
      
      def find_sent_event_by_subject(lead, subject, unsub_time)
        return nil if subject.blank?
        
        Event.where(lead: lead, event_type: :email_sent)
             .where("occurred_at < ?", unsub_time)
             .order(occurred_at: :desc)
             .find { |e| e.metadata['emailSubject'] == subject }
      end

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

        # Parse from the actual text: "Micah unsubscribed from smart plans."
        line = raw_text.lines.first.to_s.strip
        
        if line =~ /unsubscribed from ([^\.\n]+)/i
          # Extract the category and normalize it
          category = $1.strip.downcase.tr(' ', '_')
          return category
        end

        # Fallback to pattern matching if parsing fails
        text_lower = raw_text.downcase

        case text_lower
        when /seller report/
          'seller_reports'
        when /home report/
          'home_reports'
        when /market alert/, /market report/
          'market_reports'
        when /listing alert/
          'listing_alerts'
        when /property alert/
          'property_alerts'
        when /smart plan/
          'smart_plans'
        when /newsletter/
          'newsletter'
        when /email/
          'all_emails'
        else
          'unknown'
        end
      end

      def extract_manual_unsub_category(raw_text)
        return 'unknown' if raw_text.blank?

        text_lower = raw_text.downcase

        # Check for specific patterns in type 111 manual unsub events
        if text_lower.include?('disabled mass mail') && text_lower.include?('auto text') && text_lower.include?('auto email')
          'mass_mail_and_auto_messages'
        elsif text_lower.include?('market report')
          'market_reports'
        elsif text_lower.include?('property alert')
          'property_alerts'
        elsif text_lower.include?('mass mail')
          'mass_mail'
        elsif text_lower.include?('auto text')
          'auto_texts'
        elsif text_lower.include?('auto email')
          'auto_emails'
        else
          'unknown'
        end
      end

      def extract_agent_name(raw_text)
        return 'unknown' if raw_text.blank?

        # Pattern: "Alina Michelle Villarreal disabled..."
        # Extract the name before " disabled"
        if raw_text =~ /^([^\n]+?)\s+disabled/i
          $1.strip
        else
          'unknown'
        end
      end
    end
  end
end
