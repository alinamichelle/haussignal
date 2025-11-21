module Lofty
  class TimelineParser
    # Type code mappings based on observed Lofty timeline patterns
    # These map Lofty's internal type codes to our event_type enum
    TYPE_CODE_MAPPINGS = {
      5 => :email_opened,      # Manual email opened
      6 => :email_sent,        # Manual email sent
      8 => :call,              # Call activity (lead called agent)
      25 => :call,             # Call activity (agent called lead)
      37 => :email_opened,     # Alert email opened
      38 => :other,            # Pipeline change (will be detected by pipeline_change?)
      93 => :note,             # Lead details updated (system)
      98 => :note,             # Transaction assigned
      103 => :email_sent,      # MIXED: Can be email OR task - requires text check
      104 => :task,            # Task completed
      111 => :manual_unsub,    # Manual unsubscribe (agent action)
      113 => :unsub,           # Automatic unsubscribe (lead action)
      116 => :note,            # Transaction created
      120 => :note,            # Property edited
      124 => :email_sent,      # Auto email sent (can be mixed with tasks)
      128 => :email_sent,      # Auto email sent
      131 => :email_opened,    # Auto email opened
      169 => :note,            # Lead reassignment
      21 => :note,             # Profile edited
      
      # Additional type codes will be discovered and mapped as we scrape
      # Unknown codes default to :other
    }.freeze

    def self.parse(entry, lead:)
      new(entry, lead).parse
    end

    def initialize(entry, lead)
      @entry = entry
      @lead = lead
      @raw_text = entry.raw_text.to_s
      @html_content = entry.html_content.to_s
      @css_classes = entry.css_classes || []
      @data_attributes = entry.data_attributes || {}
    end

    def parse
      # Skip tasks (they're not real activities, just Lofty internal tracking)
      return nil if task_creation?(@raw_text)

      # Detect activity type and parse accordingly
      # IMPORTANT: task? must come before call? because type 104 contains "(Call)" text
      case
      when task?          then parse_task
      when call?          then parse_call
      when sms?           then parse_sms
      when email_sent?    then parse_email_sent
      when email_opened?  then parse_email_opened
      when unsub?         then parse_unsub
      when manual_unsub?  then parse_manual_unsub
      when note?          then parse_note
      when smartplan?     then parse_smartplan
      when pipeline_change? then parse_pipeline_change
      when website_activity? then parse_website_activity
      else
        parse_unknown
      end
    rescue => e
      Rails.logger.error("TimelineParser failed: #{e.class} - #{e.message}")
      Rails.logger.error("Entry: type_code=#{@entry.type_code}, text=#{@raw_text[0..100]}")
      Rails.logger.error("HTML: #{@html_content[0..500]}")
      nil
    end

    private

    # =====================================================
    # DETECTION METHODS - Identify activity type
    # =====================================================

    def call?
      # Check type code first
      return true if [8, 25].include?(@entry.type_code)
      
      @raw_text.match?(/\b(called|call|rang|phone|dialed|spoke|voicemail|answered)\b/i) ||
        @css_classes.any? { |c| c.match?(/call/i) } ||
        @html_content.match?(/icon.*phone|call.*icon/i)
    end

    def sms?
      @raw_text.match?(/\b(text|sms|message sent|message received)\b/i) ||
        @css_classes.any? { |c| c.match?(/sms|text/i) } ||
        @html_content.match?(/icon.*message|sms.*icon/i)
    end

    def email_sent?
      return false if @entry.type_code == 5 || @entry.type_code == 37 || @entry.type_code == 131
      
      [6, 124, 128, 103].include?(@entry.type_code) &&
        @raw_text.match?(/\[(Auto|Manual) E-Mail\]/i)
    end

    def email_opened?
      [5, 37, 131].include?(@entry.type_code) &&
        @raw_text.match?(/opened.*email/i)
    end

    def unsub?
      @entry.type_code == 113
    end

    def manual_unsub?
      @entry.type_code == 111
    end

    def note?
      @raw_text.match?(/\b(note|commented|added note)\b/i) ||
        @css_classes.any? { |c| c.match?(/note/i) } ||
        @html_content.match?(/icon.*note|note.*icon/i)
    end

    def task?
      # Check type code first - 104 is completed task
      return true if @entry.type_code == 104
      
      @raw_text.match?(/\b(task|reminder|follow.?up|completed task)\b/i) ||
        @css_classes.any? { |c| c.match?(/task/i) }
    end

    def task_creation?(text)
      # Tasks with "was created" are Lofty internal tracking, skip them
      text.match?(/task.*was created/i)
    end

    def smartplan?
      @raw_text.match?(/\b(smart\s*plan|drip|sequence|auto.*sent)\b/i) ||
        @css_classes.any? { |c| c.match?(/smart.*plan|drip/i) }
    end

    def pipeline_change?
      return true if @entry.type_code == 38
      
      @raw_text.match?(/\b(moved|stage.*changed|pipeline.*changed|changed.*pipeline)\b/i) ||
        @raw_text.match?(/from\s+[\w\s]+\s+to\s+[\w\s]+/i)
    end

    def website_activity?
      @raw_text.match?(/\b(visited|viewed|favorited|saved search|listing.*view)\b/i) ||
        @css_classes.any? { |c| c.match?(/website|activity|visit/i) }
    end

    # =====================================================
    # PARSE METHODS - Extract complete metadata
    # =====================================================

    def parse_call
      recording_url = extract_recording_url
      
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :call,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        recording_available: recording_url.present? || has_recording_button?,
        metadata: {
          "call_direction" => extract_call_direction,
          "call_duration_seconds" => extract_call_duration,
          "call_result" => extract_call_result,
          "call_status" => extract_call_status,
          "call_notes" => extract_call_notes,
          "caller_number" => extract_caller_number,
          "virtual_number" => extract_virtual_number,
          "lofty_recording_url" => recording_url,
          "recording_id" => extract_recording_id,
          "call_transcription" => extract_call_transcription,
          "recording_downloaded" => false,
          "recording_stored_url" => nil,
          "raw_html" => @html_content
        }
      }
    end

    def parse_sms
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :sms,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "sms_direction" => extract_sms_direction,
          "sms_body" => extract_sms_body,
          "virtual_number" => extract_virtual_number,
          "delivery_status" => extract_delivery_status,
          "raw_html" => @html_content
        }
      }
    end

    def parse_email_sent
      email_classifier = Lofty::EmailClassifier
      email_category_classifier = Lofty::EmailCategoryClassifier
      
      email_type = email_classifier.classify_email_type(@entry)
      email_subject = email_classifier.extract_email_subject(@entry)
      email_header = email_classifier.extract_email_header(@entry)
      email_id = email_classifier.extract_email_id(@entry)
      template_name = email_classifier.extract_template_name(@entry)
      email_category = email_category_classifier.classify(email_subject, email_type)

      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :email_sent,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "emailType" => email_type,
          "emailSubject" => email_subject,
          "emailHeader" => email_header,
          "emailId" => email_id,
          "templateName" => template_name,
          "rawText" => @raw_text
        },
        email_category: email_category
      }
    end

    def parse_email_opened
      email_classifier = Lofty::EmailClassifier
      email_subject = email_classifier.extract_email_subject(@entry)

      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :email_opened,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "emailSubject" => email_subject,
          "rawText" => @raw_text
        }
      }
    end

    def parse_unsub
      category = extract_unsub_category

      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :unsub,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "unsubCategory" => category,
          "leadBehavior" => @raw_text
        }
      }
    end

    def parse_manual_unsub
      category = extract_manual_unsub_category
      agent_name = extract_unsub_agent_name

      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :manual_unsub,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "unsubCategory" => category,
          "unsubType" => "manual",
          "performedBy" => agent_name,
          "leadBehavior" => @raw_text
        }
      }
    end

    def parse_note
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :note,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "note_content" => extract_note_content,
          "note_author" => extract_note_author,
          "raw_html" => @html_content
        }
      }
    end

    def parse_task
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :task,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "task_title" => extract_task_title,
          "task_status" => extract_task_status,
          "task_due_date" => extract_task_due_date,
          "task_notes" => extract_task_notes,
          "task_creator" => extract_task_creator,
          "raw_html" => @html_content
        }
      }
    end

    def parse_smartplan
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :smartplan,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "smartplan_name" => extract_smartplan_name,
          "smartplan_action" => extract_smartplan_action,
          "smartplan_actor" => extract_smartplan_actor,
          "smartplan_step_name" => extract_smartplan_step_name,
          "smartplan_step_type" => extract_smartplan_step_type,
          "smartplan_trigger" => extract_smartplan_trigger,
          "raw_html" => @html_content
        }
      }
    end

    def parse_pipeline_change
      from_stage = extract_from_stage
      to_stage = extract_to_stage
      
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :other,  # Use :other for now
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        from_pipeline: from_stage,
        to_pipeline: to_stage,
        metadata: {
          "activity_type" => "pipeline_change",
          "from" => from_stage,
          "to" => to_stage,
          "reason" => extract_change_reason,
          "actor" => extract_pipeline_actor,
          "raw_html" => @html_content
        }
      }
    end

    def parse_website_activity
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :alert_view,  # Use alert_view for website activities
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "activity_type" => "website_activity",
          "activity_details" => extract_website_details,
          "listing_url" => extract_listing_url,
          "listing_id" => extract_listing_id,
          "search_id" => extract_search_id,
          "raw_html" => @html_content
        }
      }
    end

    def parse_unknown
      {
        lofty_timeline_id: @entry.event_id,
        type_code: @entry.type_code,
        event_type: :other,
        occurred_at: parse_timestamp,
        raw_text: @raw_text,
        agent_id: extract_agent_id,
        metadata: {
          "activity_type" => "unknown",
          "raw_html" => @html_content,
          "css_classes" => @css_classes.join(" "),
          "data_attributes" => @data_attributes
        }
      }
    end

    # =====================================================
    # EXTRACTION HELPERS
    # =====================================================

    def parse_timestamp
      return Time.current if @entry.timestamp_text.blank?
      
      begin
        Time.zone.parse(@entry.timestamp_text)
      rescue
        Time.current
      end
    end

    def extract_agent_id
      # Try to find agent from lead's agent_id or parse from text
      agent_name = extract_agent_name_from_text
      return nil if agent_name.blank?
      
      # Look up agent by name
      Agent.find_by("name ILIKE ?", agent_name)&.id || @lead.agent_id
    end

    def extract_agent_name_from_text
      # Pattern: "Agent Name did something" or "[Manual E-Mail] Agent Name to Lead:"
      if @raw_text =~ /\[(?:Auto|Manual) E-Mail\]\s*([^:]+)\s+(?:to|sent)/i
        return $1.strip
      end
      
      # Pattern: "Agent Name disabled..." or "Agent Name moved..."
      if @raw_text =~ /^([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(?:disabled|moved|added|called)/i
        return $1.strip
      end
      
      nil
    end

    # Call-specific extractors
    def extract_call_direction
      return "inbound" if @raw_text.match?(/rang|received|incoming|lead called/i)
      return "outbound" if @raw_text.match?(/agent called|called lead|dialed|outgoing/i)
      return "outbound" if @raw_text.match?(/^[A-Z][a-z]+ [A-Z][a-z]+ called/i)  # "Matt Cordova called"
      "unknown"
    end

    def extract_call_duration
      # Look for patterns like "2:34", "1 min 23 sec", "45 seconds"
      if @raw_text =~ /(\d+):(\d+)/
        minutes = $1.to_i
        seconds = $2.to_i
        return minutes * 60 + seconds
      end
      
      if @raw_text =~ /(\d+)\s*min/i
        return $1.to_i * 60
      end
      
      if @raw_text =~ /(\d+)\s*sec/i
        return $1.to_i
      end
      
      nil
    end

    def extract_call_result
      return "answered" if @raw_text.match?(/answered|spoke|talked/i)
      return "voicemail" if @raw_text.match?(/voicemail|left.*message/i)
      return "no_answer" if @raw_text.match?(/no.*answer|unanswered/i)
      return "busy" if @raw_text.match?(/busy/i)
      "other"
    end

    def extract_call_notes
      # Extract any text after the main call description
      lines = @raw_text.lines.map(&:strip).reject(&:blank?)
      
      # Skip first line (main description) and last line if it's a timestamp
      return nil if lines.length <= 1
      
      notes_lines = lines[1..-1]
      
      # Remove timestamp line if present (format: "Nov 19, 2025 at 03:05:07 PM")
      notes_lines = notes_lines.reject { |line| line.match?(/^[A-Z][a-z]{2}\s+\d{1,2},\s+\d{4}\s+at\s+\d{1,2}:\d{2}:\d{2}\s+[AP]M$/i) }
      
      notes_text = notes_lines.join("\n").strip
      notes_text.present? ? notes_text : nil
    end

    def extract_call_status
      # Extract status like "Completed", "Missed", "Cancelled"
      return "completed" if @raw_text.match?(/completed|successful/i)
      return "missed" if @raw_text.match?(/missed|unanswered/i)
      return "cancelled" if @raw_text.match?(/cancelled|declined/i)
      return "failed" if @raw_text.match?(/failed/i)
      "unknown"
    end

    def extract_caller_number
      # Extract caller's phone number from text or data attributes
      # Pattern: "called Lead (+1 5125791357)"
      if @raw_text =~ /\(\+?1?\s*(\d{3})[-.\s]?(\d{3})[-.\s]?(\d{4})\)/
        return "#{$1}-#{$2}-#{$3}"
      end
      
      if @raw_text =~ /from\s+(\+?1?\s*\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4})/i
        return normalize_phone_number($1)
      end
      
      @data_attributes['caller-number'] || @data_attributes['from-number']
    end

    def extract_recording_url
      # Look for download link in HTML
      return @entry.audio_url if @entry.audio_url.present?
      
      # Try to extract from data attributes
      @data_attributes['recording-url'] ||
        @data_attributes['audio-url'] ||
        @data_attributes['call-recording'] ||
        extract_url_from_html(@html_content, /download.*recording|recording.*download/i)
    end

    def extract_recording_id
      # Extract recording ID from URL or data attributes
      if extract_recording_url =~ /recording[_-]?(\d+)/i
        return $1
      end
      
      @data_attributes['recording-id'] || @data_attributes['call-recording-id']
    end

    def extract_call_transcription
      # Look for transcription text in HTML or data attributes
      # Lofty may add this feature in the future
      @data_attributes['transcription'] || @data_attributes['call-transcript']
    end

    def has_recording_button?
      # Check if HTML contains recording download button/icon
      @html_content.match?(/download.*recording|recording.*download|icon.*download.*audio/i) ||
        @css_classes.any? { |c| c.match?(/recording|audio.*download/i) } ||
        @data_attributes.keys.any? { |k| k.match?(/recording|audio/i) }
    end

    def normalize_phone_number(phone)
      # Normalize to consistent format
      digits = phone.gsub(/\D/, '')
      return nil if digits.length < 10
      
      digits = digits[-10..-1] if digits.length > 10
      "#{digits[0..2]}-#{digits[3..5]}-#{digits[6..9]}"
    end

    def extract_url_from_html(html, pattern)
      # Extract URL matching pattern from HTML
      return nil if html.blank?
      
      if html =~ /href=["']([^"']+)["']/i && $1.match?(pattern)
        return $1
      end
      nil
    end

    # SMS-specific extractors
    def extract_sms_direction
      return "inbound" if @raw_text.match?(/received|from lead|incoming/i)
      return "outbound" if @raw_text.match?(/sent|to lead|outgoing/i)
      "unknown"
    end

    def extract_sms_body
      # Enhanced SMS body extraction for threads, nested HTML, long messages
      
      # Try to extract from HTML first (handles nested blocks)
      if @html_content.present?
        # Look for message content in div/p tags
        if @html_content =~ /<div[^>]*class=["'][^"']*message[^"']*["'][^>]*>(.+?)<\/div>/im
          body = $1.gsub(/<[^>]+>/, ' ').strip  # Strip HTML tags
          return body if body.length > 10
        end
        
        if @html_content =~ /<p[^>]*>(.+?)<\/p>/im
          body = $1.gsub(/<[^>]+>/, ' ').strip
          return body if body.length > 10  
        end
      end
      
      # Fall back to raw text parsing
      lines = @raw_text.lines.map(&:strip).reject(&:blank?)
      
      # Skip first line if it's a header (like "SMS sent to Lead:")
      if lines.length > 1 && lines[0].match?(/SMS|Text|sent|received|at\s+\d{2}:/i)
        body = lines[1..-1].join("\n")
        return body if body.present?
      end
      
      # Return full text if no better option
      @raw_text
    end

    def extract_virtual_number
      # Look for phone number patterns in text or data attributes
      if @raw_text =~ /\+?1?\s*\(?(\d{3})\)?[-.\s]?(\d{3})[-.\s]?(\d{4})/
        return "#{$1}-#{$2}-#{$3}"
      end
      
      @data_attributes['phone'] || @data_attributes['number']
    end

    def extract_delivery_status
      return "delivered" if @raw_text.match?(/delivered/i)
      return "failed" if @raw_text.match?(/failed|error/i)
      return "pending" if @raw_text.match?(/pending|sending/i)
      nil
    end

    # Note-specific extractors
    def extract_note_content
      @raw_text
    end

    def extract_note_author
      extract_agent_name_from_text
    end

    # Task-specific extractors
    def extract_task_title
      # First line is usually the task title
      @raw_text.lines.first&.strip
    end

    def extract_task_status
      return "completed" if @raw_text.match?(/completed|done|finished/i)
      return "pending" if @raw_text.match?(/pending|upcoming/i)
      "unknown"
    end

    def extract_task_due_date
      # Look for due date patterns in text or data attributes
      if @raw_text =~ /due[:\s]+([\w\s,]+)/i
        begin
          return Time.zone.parse($1)
        rescue
          nil
        end
      end
      
      if @data_attributes['due-date'] || @data_attributes['duedate']
        begin
          return Time.zone.parse(@data_attributes['due-date'] || @data_attributes['duedate'])
        rescue
          nil
        end
      end
      
      nil
    end

    def extract_task_notes
      lines = @raw_text.lines.map(&:strip).reject(&:blank?)
      lines.length > 1 ? lines[1..-1].join("\n") : nil
    end

    def extract_task_creator
      return "auto" if @raw_text.match?(/auto.*email|smart.*plan|drip/i)
      "manual"
    end

    # Smartplan-specific extractors
    def extract_smartplan_action
      # Extract action: applied, deleted, paused, resumed, completed, etc.
      return "applied" if @raw_text.match?(/applied\s+smart\s*plan/i)
      return "deleted" if @raw_text.match?(/deleted\s+smart\s*plan/i)
      return "paused" if @raw_text.match?(/paused\s+smart\s*plan/i)
      return "resumed" if @raw_text.match?(/resumed\s+smart\s*plan/i)
      return "completed" if @raw_text.match?(/completed\s+smart\s*plan/i)
      return "started" if @raw_text.match?(/started\s+smart\s*plan/i)
      "unknown"
    end
    
    def extract_smartplan_actor
      # Extract who performed the action
      # Pattern: "Agent Name applied Smart Plan"
      if @raw_text =~ /^([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:\s+[A-Z][a-z]+)?)\s+(?:applied|deleted|paused|resumed|completed|started)/i
        return $1.strip
      end
      
      # Fallback to generic agent extraction
      extract_agent_name_from_text
    end
    
    def extract_smartplan_name
      # Try to extract smart plan name from text
      if @raw_text =~ /smart\s*plan[:\s]+([^,\n]+)/i
        return $1.strip
      end
      
      # Look in data attributes
      @data_attributes['smartplan-name'] || @data_attributes['plan-name']
    end

    def extract_smartplan_step_name
      # Extract step name like "Market Snapshot" or "Follow Up Call"
      if @raw_text =~ /step[:\s]+([^,\n]+)/i
        return $1.strip
      end
      
      # May be in the format: "Auto Email: Market Snapshot was sent"
      if @raw_text =~ /auto\s+(?:email|text)[:\s]+([^\n]+?)\s+(?:was|sent)/i
        return $1.strip
      end
      
      @data_attributes['step-name'] || @data_attributes['smartplan-step']
    end

    def extract_smartplan_step_type
      return "email" if @raw_text.match?(/auto.*email/i)
      return "sms" if @raw_text.match?(/auto.*text|auto.*sms/i)
      return "task" if @raw_text.match?(/task.*created/i)
      return "notification" if @raw_text.match?(/notification/i)
      "other"
    end

    def extract_smartplan_trigger
      return "auto" if @raw_text.match?(/automatically|auto/i)
      return "manual" if @raw_text.match?(/manually/i)
      "auto"
    end

    # Pipeline change extractors
    def extract_from_stage
      # Pattern: "from Stage1 to Stage2"
      if @raw_text =~ /from\s+([^to]+)\s+to/i
        return $1.strip
      end
      
      # Pattern: "changed pipeline from Stage1"
      if @raw_text =~ /pipeline\s+from\s+([^\n]+?)\s+to/i
        return $1.strip
      end
      
      # Look in HTML for hidden from value
      if @html_content =~ /data-from-pipeline=["']([^"']+)["']/i
        return $1.strip
      end
      
      nil
    end

    def extract_to_stage
      # Pattern: "to Stage" or "Moved to Stage"
      if @raw_text =~ /(?:to|moved to)\s+([^\n,\.]+)/i
        stage = $1.strip
        # Clean up common suffixes
        stage = stage.sub(/\s*view details$/i, '')
        stage = stage.sub(/\s*from.*$/i, '')  # Remove any "from" text
        return stage if stage.present?
      end
      
      # Look in HTML for hidden to value  
      if @html_content =~ /data-to-pipeline=["']([^"']+)["']/i
        return $1.strip
      end
      
      # Pattern: just "Stage Name" after "changed pipeline"
      if @raw_text =~ /changed.*pipeline[:\s]+([^\n\.]+)/i
        return $1.strip
      end
      
      nil
    end

    def extract_pipeline_actor
      # Extract who made the pipeline change
      # Pattern: "Agent Name changed Lead's pipeline"
      if @raw_text =~ /^([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:\s+[A-Z][a-z]+)?)\s+changed/i
        return $1.strip
      end
      
      # Fallback to generic agent extraction
      extract_agent_name_from_text
    end

    def extract_change_reason
      # Look for reason in parentheses or after colon
      if @raw_text =~ /\(([^)]+)\)/
        return $1.strip
      end
      nil
    end

    # Website activity extractors
    def extract_website_details
      @raw_text
    end

    def extract_listing_url
      # Extract listing URL from HTML or data attributes
      if @html_content =~ /href=["']([^"']*listing[^"']*)["']/i
        return $1
      end
      
      @data_attributes['listing-url'] || @data_attributes['property-url']
    end

    def extract_listing_id
      # Extract listing/property ID from URL or data attributes
      url = extract_listing_url
      if url =~ /listing[_\/-](\d+)/i
        return $1
      end
      
      if url =~ /property[_\/-](\d+)/i
        return $1
      end
      
      @data_attributes['listing-id'] || @data_attributes['property-id']
    end

    def extract_search_id
      # Extract saved search ID
      if @raw_text =~ /search[:\s]+(\d+)/i
        return $1
      end
      
      @data_attributes['search-id'] || @data_attributes['saved-search-id']
    end

    # Unsub extractors (from existing code)
    def extract_unsub_category
      return 'unknown' if @raw_text.blank?

      line = @raw_text.lines.first.to_s.strip
      
      if line =~ /unsubscribed from ([^\.\\n]+)/i
        category = $1.strip.downcase.tr(' ', '_')
        return category
      end

      'unknown'
    end

    def extract_manual_unsub_category
      return 'unknown' if @raw_text.blank?

      text_lower = @raw_text.downcase

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

    def extract_unsub_agent_name
      return 'unknown' if @raw_text.blank?

      # Pattern: "Agent Name disabled..."
      if @raw_text =~ /^([^\\n]+?)\\s+disabled/i
        $1.strip
      else
        'unknown'
      end
    end
  end
end
