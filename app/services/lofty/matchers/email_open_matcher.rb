module Lofty
  module Matchers
    class EmailOpenMatcher
      # sent_event: Event (email_sent)
      # candidate_opens: Array<Event> (email_opened for same lead)
      def initialize(sent_event, candidate_opens)
        @sent_event      = sent_event
        @candidate_opens = candidate_opens
      end

      def call
        candidates = @candidate_opens.compact
        return nil if candidates.empty? || @sent_event.occurred_at.nil?

        # 1. same subject (normalized)
        by_subject = candidates.find do |ev|
          normalize_subject(ev.metadata["emailSubject"]) ==
            normalize_subject(@sent_event.metadata["emailSubject"])
        end
        return by_subject if by_subject

        # 2. same listing URL (if present)
        sent_url = @sent_event.metadata["listingUrl"]
        if sent_url.present?
          by_url = candidates.find do |ev|
            ev.metadata["listingUrl"].present? &&
              ev.metadata["listingUrl"] == sent_url
          end
          return by_url if by_url
        end

        # 3. within ±5 minutes of send time (closest in time)
        by_time = candidates
          .select { |ev| ev.occurred_at.present? }
          .min_by { |ev| (ev.occurred_at - @sent_event.occurred_at).abs }

        if by_time && (by_time.occurred_at - @sent_event.occurred_at).abs <= 5.minutes
          return by_time
        end

        nil
      end

      private

      def normalize_subject(subject)
        subject.to_s.downcase.gsub(/\s+/, " ").strip
      end
    end
  end
end
