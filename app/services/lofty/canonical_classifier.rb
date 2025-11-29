# frozen_string_literal: true

module Lofty
  class CanonicalClassifier
    def self.classify(type_code:, raw_text:, parsed_event: {})
      mapping = TypeCodeMap.lookup(type_code)

      # Fallback for unknown / unmapped codes
      if mapping.nil?
        Rails.logger.warn "Unknown type_code in CanonicalClassifier: #{type_code}"
        return {
          canonical_event_type: :unknown_event,
          category:   :system_internal,
          channel:    :system,
          auto:       true,
          source:     'lofty'
        }
      end

      # If mapping has a handler, call it
      if mapping[:handler]
        return send(mapping[:handler], raw_text, parsed_event)
      end

      # Return static mapping - store rich type as canonical_event_type, not event_type
      result = mapping.slice(
        :category,
        :channel,
        :auto,
        :direction,
        :marketing_kind,
        :communication_kind,
        :task_origin,
        :smart_plan_step_kind,
        :profile_change_type,
        :source
      ).compact
      
      # Store the rich canonical type separately (not in event_type)
      result[:canonical_event_type] = mapping[:event_type] if mapping[:event_type]
      result
    end

    # ==========================================
    # HANDLERS FOR AMBIGUOUS TYPE CODES
    # ==========================================

    # Type 103: Email OR smart-plan task
    # Check raw_text for email patterns vs task patterns
    def self.handle_103(raw_text, parsed_event)
      if raw_text.to_s.match?(/\[(Auto|Manual)\s+E-Mail\]/i)
        {
          canonical_event_type: :email_sent_auto,
          category:       :marketing,
          marketing_kind: :outbound,
          channel:        :email,
          auto:           true,
          source:         'lofty'
        }
      else
        {
          canonical_event_type: :task_completed_auto,
          category:     :task,
          task_origin:  :smart_plan,
          channel:      :system,
          auto:         true,
          source:       'lofty'
        }
      end
    end

    # Type 170: Scheduled email sent
    def self.handle_170(raw_text, parsed_event)
      {
        canonical_event_type: :email_sent_scheduled,
        category:           :communication,
        communication_kind: :manual,
        channel:            :email,
        direction:          :outbound,
        auto:               false,
        source:             'lofty'
      }
    end

    # Type 11: Property alert / details email
    # Sample: "$1,150,000, 309 Wolf Ridge RD..."
    def self.handle_11(raw_text, parsed_event)
      {
        canonical_event_type: :property_alert_sent,
        category:       :marketing,
        marketing_kind: :outbound,
        channel:        :email,
        auto:           true,
        source:         'lofty'
      }
    end

    # Type 127: Property preferences ("2 full and 1 half")
    # Check if it's a bathroom/property preference or just noise
    def self.handle_127(raw_text, parsed_event)
      if raw_text.to_s.match?(/\d+\s+(full|half|bath)/i)
        {
          canonical_event_type: :property_preference_updated,
          category:            :profile,
          profile_change_type: :contact_info_change,
          channel:             :system,
          auto:                true,
          source:              'lofty'
        }
      else
        {
          canonical_event_type: :system_noise,
          category:   :system_internal,
          channel:    :system,
          auto:       true,
          source:     'lofty'
        }
      end
    end
  end
end
