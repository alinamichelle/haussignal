module Lofty
  class UnsubAttributionService
    def initialize
      @classifier = Lofty::EmailClassifier
    end
    
    # Main method: finds trigger email and builds full attribution metadata
    def attribute_unsub(unsub_entry, all_entries)
      unsub_time = parse_timestamp(unsub_entry.timestamp_text)
      
      # Find all email sent events before the unsub
      eligible_emails = find_eligible_emails(all_entries, unsub_time)
      
      return nil if eligible_emails.empty?
      
      # Choose the best trigger email
      trigger_email = select_trigger_email(eligible_emails, unsub_time)
      
      return nil unless trigger_email
      
      # Find if this email was opened
      open_event = find_open_event(trigger_email, all_entries, unsub_time)
      
      # Build complete metadata
      build_attribution_metadata(trigger_email, open_event, unsub_entry, unsub_time)
    end
    
    private
    
    def find_eligible_emails(all_entries, unsub_time)
      eligible = all_entries.select do |entry|
        # Must be an email sent event
        is_email = @classifier.is_email_sent?(entry.type_code)
        next false unless is_email
        
        # Must occur before unsub
        entry_time = parse_timestamp(entry.timestamp_text)
        next false unless entry_time < unsub_time
        
        true
      end.sort_by { |entry| parse_timestamp(entry.timestamp_text) }.reverse
      
      Rails.logger.info "  🔍 Found #{eligible.length} eligible email(s) before unsub"
      eligible.each do |e|
        Rails.logger.info "     - Type #{e.type_code}: #{@classifier.extract_email_subject(e)&.[](0..50)}"
      end
      
      eligible
    end
    
    def select_trigger_email(eligible_emails, unsub_time)
      # If only one email, return it
      return eligible_emails.first if eligible_emails.length == 1
      
      # Score each email based on:
      # 1. Email type weight (mass emails > alerts)
      # 2. Time proximity to unsub
      # 3. Presence of subject/metadata
      
      scored_emails = eligible_emails.map do |email|
        email_type = @classifier.classify_email_type(email)
        type_weight = @classifier.email_type_weight(email_type)
        
        email_time = parse_timestamp(email.timestamp_text)
        time_diff = (unsub_time - email_time).abs
        
        # Prefer emails sent within last 7 days
        recency_score = if time_diff < 1.hour
          10
        elsif time_diff < 1.day
          8
        elsif time_diff < 3.days
          5
        elsif time_diff < 7.days
          3
        else
          1
        end
        
        # Bonus points for having subject
        subject = @classifier.extract_email_subject(email)
        metadata_score = subject.present? ? 2 : 0
        
        total_score = (type_weight * 2) + recency_score + metadata_score
        
        { email: email, score: total_score, time_diff: time_diff }
      end
      
      # Sort by score descending, then by time proximity
      scored_emails.sort_by { |item| [-item[:score], item[:time_diff]] }.first[:email]
    end
    
    def find_open_event(trigger_email, all_entries, unsub_time)
      email_id = @classifier.extract_email_id(trigger_email)
      email_subject = @classifier.extract_email_subject(trigger_email)
      email_time = parse_timestamp(trigger_email.timestamp_text)
      
      # Find open events between email send and unsub
      all_entries.find do |entry|
        next false unless @classifier.is_email_opened?(entry.type_code)
        
        entry_time = parse_timestamp(entry.timestamp_text)
        next false unless entry_time > email_time && entry_time < unsub_time
        
        # Try to match by email ID first
        if email_id.present?
          entry_email_id = @classifier.extract_email_id(entry)
          return entry if entry_email_id == email_id
        end
        
        # Fallback: match by subject
        if email_subject.present?
          entry_subject = @classifier.extract_email_subject(entry)
          return entry if entry_subject == email_subject
        end
        
        # Fallback: if there's only one open event in the time window
        # we can assume it's for this email
        false
      end
    end
    
    def build_attribution_metadata(trigger_email, open_event, unsub_entry, unsub_time)
      email_type = @classifier.classify_email_type(trigger_email)
      email_subject = @classifier.extract_email_subject(trigger_email)
      email_id = @classifier.extract_email_id(trigger_email)
      template_name = @classifier.extract_template_name(trigger_email)
      email_header = @classifier.extract_email_header(trigger_email)
      
      sent_at = parse_timestamp(trigger_email.timestamp_text)
      
      metadata = {
        emailId: email_id,
        emailType: email_type,
        emailSubject: email_subject,
        emailHeader: email_header,
        emailTemplateName: template_name,
        sentAt: sent_at.iso8601,
        openStatus: open_event ? 'opened' : 'not_opened'
      }
      
      if open_event
        opened_at = parse_timestamp(open_event.timestamp_text)
        metadata[:openedAt] = opened_at.iso8601
        
        # Calculate time intervals
        metadata[:secondsFromSendToOpen] = (opened_at - sent_at).to_i
        metadata[:secondsFromSendToUnsub] = (unsub_time - sent_at).to_i
        metadata[:secondsFromOpenToUnsub] = (unsub_time - opened_at).to_i
      else
        metadata[:openedAt] = nil
        metadata[:secondsFromSendToOpen] = nil
        metadata[:secondsFromSendToUnsub] = (unsub_time - sent_at).to_i
        metadata[:secondsFromOpenToUnsub] = nil
      end
      
      # Add context flags for AI coaching
      metadata[:unsubContext] = build_context_flags(
        trigger_email, 
        open_event, 
        email_type,
        metadata[:secondsFromSendToUnsub],
        metadata[:secondsFromOpenToUnsub]
      )
      
      metadata
    end
    
    def build_context_flags(trigger_email, open_event, email_type, send_to_unsub, open_to_unsub)
      context = {}
      
      # Was the email opened?
      context[:emailOpened] = open_event.present?
      
      # Quick unsub after opening? (within 5 minutes)
      if open_to_unsub && open_to_unsub < 300
        context[:quickUnsubAfterOpen] = true
      end
      
      # Unsub without opening?
      if !open_event && send_to_unsub
        context[:unsubWithoutOpening] = true
      end
      
      # Was it an automated/drip campaign?
      context[:wasAutomatedCampaign] = email_type == 'smart_plan'
      
      # Was it a mass email blast?
      context[:wasMassEmail] = email_type == 'mass_email'
      
      # Was it an alert/report?
      context[:wasAlert] = ['listing_alert', 'property_alert', 'market_report', 'seller_report', 'home_report'].include?(email_type)
      
      # Time-based context
      if send_to_unsub
        if send_to_unsub < 60
          context[:unsubTiming] = 'immediate' # within 1 minute
        elsif send_to_unsub < 3600
          context[:unsubTiming] = 'within_hour'
        elsif send_to_unsub < 86400
          context[:unsubTiming] = 'same_day'
        elsif send_to_unsub < 604800
          context[:unsubTiming] = 'within_week'
        else
          context[:unsubTiming] = 'later'
        end
      end
      
      context
    end
    
    def parse_timestamp(timestamp_text)
      return Time.current if timestamp_text.blank?
      
      begin
        # Try standard parsing first
        parsed = Time.zone.parse(timestamp_text)
        return parsed if parsed
      rescue
        # Fallback patterns for Lofty's relative timestamps
        
        # "X minutes ago"
        if timestamp_text =~ /(\d+)\s*minutes?\s*ago/i
          return $1.to_i.minutes.ago
        end
        
        # "X hours ago"
        if timestamp_text =~ /(\d+)\s*hours?\s*ago/i
          return $1.to_i.hours.ago
        end
        
        # "X days ago"
        if timestamp_text =~ /(\d+)\s*days?\s*ago/i
          return $1.to_i.days.ago
        end
        
        # "Yesterday"
        if timestamp_text =~ /yesterday/i
          return 1.day.ago
        end
        
        # "Today at HH:MM AM/PM"
        if timestamp_text =~ /today\s+at\s+(\d+):(\d+)\s*(am|pm)/i
          hour = $1.to_i
          minute = $2.to_i
          meridiem = $3.downcase
          
          hour += 12 if meridiem == 'pm' && hour != 12
          hour = 0 if meridiem == 'am' && hour == 12
          
          return Time.zone.now.change(hour: hour, min: minute)
        end
      end
      
      # Ultimate fallback
      Time.current
    end
  end
end
