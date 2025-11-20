module Lofty
  class EmailClassifier
    # Type code mappings based on Lofty's timeline system
    # Type 6 = Manual email sent (primary)
    # Type 103 = MIXED! Can be email sends OR tasks - must check text
    # Type 124 = MIXED! Can be email sends OR tasks - must check text  
    # Type 128 = Auto email sent
    # Type 105 = Task completion (NOT email)
    # Type 37 = Alert email opens
    # Type 126 = SMS/text messages (not emails)
    # Type 127 = SMS/text messages (not emails)
    EMAIL_SENT_CODES = [6, 103, 124, 128].freeze
    EMAIL_OPENED_CODES = [37].freeze
    SMS_CODES = [126].freeze
    
    # Email type badges/labels commonly used in Lofty
    EMAIL_TYPE_PATTERNS = {
      mass_email: [
        /mass\s*email/i,
        /email\s*campaign/i,
        /broadcast/i
      ],
      smart_plan: [
        /smart\s*plan/i,
        /drip/i,
        /automated\s*sequence/i,
        /nurture/i
      ],
      listing_alert: [
        /listing\s*alert/i,
        /new\s*listing/i,
        /property\s*match/i,
        /new\s*homes\s*for/i,
        /price\s*reduced/i,
        /status\s*changed/i
      ],
      property_alert: [
        /property\s*alert/i,
        /home\s*alert/i,
        /alert\s*email/i
      ],
      market_report: [
        /market\s*report/i,
        /cma/i,
        /comparative\s*market/i
      ],
      seller_report: [
        /seller\s*report/i,
        /home\s*value/i
      ],
      home_report: [
        /home\s*report/i,
        /buyer\s*report/i
      ],
      newsletter: [
        /newsletter/i
      ]
    }.freeze
    
    def self.classify_email_type(entry)
      # Try CSS classes first
      email_type = classify_from_css_classes(entry.css_classes)
      return email_type if email_type
      
      # Try HTML content patterns
      email_type = classify_from_html(entry.html_content)
      return email_type if email_type
      
      # Try raw text patterns
      email_type = classify_from_text(entry.raw_text)
      return email_type if email_type
      
      # Fallback based on type code
      classify_from_type_code(entry.type_code)
    end
    
    def self.is_email_sent?(type_code, raw_text = nil)
      # Type 103 and 124 are MIXED - check text to distinguish emails from tasks
      if [103, 124].include?(type_code)
        # It's a task if text says "Task: ... was created" or "Task was created"
        return false if raw_text&.match?(/task.*was created/i)
        # It's an email if text has [Auto E-Mail] or [Manual E-Mail] header
        return true if raw_text&.match?(/\[(Auto|Manual) E-Mail\]/i)
        # Otherwise unclear, default to false to be safe
        return false
      end
      
      # Other codes are straightforward
      EMAIL_SENT_CODES.include?(type_code)
    end
    
    def self.is_email_opened?(type_code)
      EMAIL_OPENED_CODES.include?(type_code)
    end
    
    def self.is_task?(raw_text)
      raw_text&.match?(/task was created/i)
    end
    
    def self.extract_email_subject(entry)
      # Try data attributes first
      subject = entry.data_attributes['email-subject'] || 
                entry.data_attributes['subject'] ||
                entry.data_attributes['emailsubject']
      return subject if subject.present?
      
      # Try extracting from HTML
      subject = extract_subject_from_html(entry.html_content)
      return subject if subject.present?
      
      # Try extracting from raw text
      extract_subject_from_text(entry.raw_text)
    end
    
    def self.extract_email_header(entry)
      # Extract the "[Auto E-Mail] Sender to Recipient:" line
      return nil if entry.raw_text.blank?
      
      lines = entry.raw_text.lines.map(&:strip).reject(&:blank?)
      return nil if lines.empty?
      
      # Look for the email header pattern
      first_line = lines.first
      if first_line&.match?(/\[Auto E-Mail\].*:/i)
        return first_line
      end
      
      nil
    end
    
    def self.extract_email_id(entry)
      entry.data_attributes['email-id'] ||
        entry.data_attributes['emailid'] ||
        entry.data_attributes['message-id'] ||
        entry.data_attributes['messageid']
    end
    
    def self.extract_template_name(entry)
      # Try data attributes
      template = entry.data_attributes['template-name'] ||
                 entry.data_attributes['template'] ||
                 entry.data_attributes['templatename']
      return template if template.present?
      
      # Try extracting from HTML (look for template badges/labels)
      extract_template_from_html(entry.html_content)
    end
    
    def self.email_type_weight(email_type)
      # Weight system for choosing which email to attribute unsub to
      weights = {
        mass_email: 5,
        newsletter: 4,
        smart_plan: 3,
        listing_alert: 2,
        property_alert: 2,
        market_report: 2,
        seller_report: 2,
        home_report: 2,
        unknown: 1
      }
      weights[email_type.to_sym] || 1
    end
    
    private
    
    def self.classify_from_css_classes(css_classes)
      return nil if css_classes.blank?
      
      combined = css_classes.join(' ')
      
      EMAIL_TYPE_PATTERNS.each do |type, patterns|
        patterns.each do |pattern|
          return type.to_s if combined.match?(pattern)
        end
      end
      
      nil
    end
    
    def self.classify_from_html(html_content)
      return nil if html_content.blank?
      
      EMAIL_TYPE_PATTERNS.each do |type, patterns|
        patterns.each do |pattern|
          return type.to_s if html_content.match?(pattern)
        end
      end
      
      nil
    end
    
    def self.classify_from_text(raw_text)
      return nil if raw_text.blank?
      
      EMAIL_TYPE_PATTERNS.each do |type, patterns|
        patterns.each do |pattern|
          return type.to_s if raw_text.match?(pattern)
        end
      end
      
      nil
    end
    
    def self.classify_from_type_code(type_code)
      # Fallback classification based on type code alone
      case type_code
      when 103, 105
        'email'
      when 124
        'email_opened'
      else
        'unknown'
      end
    end
    
    def self.extract_subject_from_html(html_content)
      return nil if html_content.blank?
      
      # Try common patterns in Lofty's HTML structure
      # Look for subject in various HTML patterns
      if html_content =~ /<div[^>]*class="[^"]*subject[^"]*"[^>]*>([^<]+)<\/div>/i
        return $1.strip
      end
      
      if html_content =~ /<span[^>]*class="[^"]*subject[^"]*"[^>]*>([^<]+)<\/span>/i
        return $1.strip
      end
      
      # Look for strong/bold subject lines
      if html_content =~ /<strong>([^<]+)<\/strong>/i
        candidate = $1.strip
        return candidate if candidate.length > 10 && candidate.length < 200
      end
      
      nil
    end
    
    def self.extract_subject_from_text(raw_text)
      return nil if raw_text.blank?
      
      lines = raw_text.lines.map(&:strip).reject(&:blank?)
      return nil if lines.empty?
      
      # Look for "Subject:" pattern
      subject_line = lines.find { |line| line.match?(/^subject:/i) }
      if subject_line
        return subject_line.sub(/^subject:\s*/i, '').strip
      end
      
      # Look for "Re:" or "Fwd:" patterns
      reply_line = lines.find { |line| line.match?(/^(re|fwd):/i) }
      return reply_line.strip if reply_line
      
      # Special handling for Lofty's email format:
      # Line 1: "[Auto E-Mail] Name to Name:" or "[Manual E-Mail] Name to Name:"
      # Line 2: Actual subject
      if lines.length >= 2 && lines[0].match?(/\[(Auto|Manual) E-Mail\].*:/i)
        # The real subject is on the second line
        return lines[1] if lines[1].length > 5
      end
      
      # Return first line if it looks like a subject (not too short, not too long)
      first_line = lines.first
      if first_line && first_line.length > 5 && first_line.length < 200
        return first_line
      end
      
      nil
    end
    
    def self.extract_template_from_html(html_content)
      return nil if html_content.blank?
      
      # Look for template badges/labels in HTML
      if html_content =~ /<span[^>]*class="[^"]*badge[^"]*"[^>]*>([^<]+)<\/span>/i
        return $1.strip
      end
      
      if html_content =~ /<div[^>]*class="[^"]*template[^"]*"[^>]*>([^<]+)<\/div>/i
        return $1.strip
      end
      
      nil
    end
  end
end
