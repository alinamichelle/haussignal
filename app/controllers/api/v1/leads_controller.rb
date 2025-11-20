module Api
  module V1
    class LeadsController < BaseController
      UNSUB_EVENT_TYPES  = %w[unsub manual_unsub].freeze
      EMAIL_SENT_TYPES   = %w[email_sent].freeze
      EMAIL_OPENED_TYPES = %w[email_opened].freeze

      # GET /api/v1/leads/:id/unsub_details
      # Returns full lead history and unsub details
      # NOTE: This endpoint ignores dashboard filters and shows complete lead history
      def unsub_details
        lead = Lead.includes(:agent).find(params[:id])

        # Find most recent unsub event (use raw Event, not scoped_events)
        unsub_event = Event.where(
          lead_id: lead.id,
          event_type: UNSUB_EVENT_TYPES
        ).order(occurred_at: :desc).first

        # If no unsub event exists, return basic lead info with nulls
        unless unsub_event
          render json: {
            lead: build_lead_payload(lead),
            unsubEvent: nil,
            engagementBefore: nil,
            recentActivity: build_recent_activity(lead)
          }
          return
        end

        # Calculate engagement metrics before unsub
        sent_before = Event.where(
          lead_id: lead.id,
          event_type: EMAIL_SENT_TYPES
        ).where('occurred_at <= ?', unsub_event.occurred_at).count

        opened_before = Event.where(
          lead_id: lead.id,
          event_type: EMAIL_OPENED_TYPES
        ).where('occurred_at <= ?', unsub_event.occurred_at).count

        days_active = lead.reg_date ? (unsub_event.occurred_at.to_date - lead.reg_date.to_date).to_i : nil
        open_rate = sent_before.zero? ? 0 : (opened_before.to_f / sent_before).round(4)

        render json: {
          lead: build_lead_payload(lead),
          unsubEvent: {
            unsubscribedFromCampaignId: unsub_event.metadata['campaign_id'],
            unsubscribedFromSubject:    unsub_event.metadata['emailSubject'] || unsub_event.metadata['triggerEmail']&.dig('emailSubject'),
            unsubscribedAt:             unsub_event.occurred_at,
            type:                       unsub_event.metadata['emailType'] || unsub_event.event_type
          },
          engagementBefore: {
            emailsSent: sent_before,
            emailsOpened: opened_before,
            daysActive: days_active,
            openRate: open_rate
          },
          recentActivity: build_recent_activity(lead)
        }
      end

      private

      def build_lead_payload(lead)
        {
          id: lead.id,
          name: lead.full_name || [lead.first_name, lead.last_name].compact.join(' '),
          email: lead.email,
          phone: lead.phone,
          agentName: lead.agent&.name,
          pipeline: lead.pipeline,
          regDate: lead.reg_date,
          tags: lead.tags || []
        }
      end

      def build_recent_activity(lead)
        Event.where(lead_id: lead.id)
             .order(occurred_at: :desc)
             .limit(10)
             .map do |e|
          {
            type: e.event_type,
            label: e.raw_text&.truncate(80) || e.event_type.titleize,
            at: e.occurred_at
          }
        end
      end
    end
  end
end
