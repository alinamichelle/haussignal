module Api
  module V1
    class AnalyticsController < BaseController
      # GET /api/v1/analytics/overview
      # Returns high-level stats about all leads and events
      def overview
        # Lead stats
        total_leads = Lead.count
        synced_leads = Lead.where.not(timeline_synced_at: nil).count
        
        # Event stats
        total_events = Event.count
        event_type_counts = Event.group(:event_type).count
        
        # Email stats
        emails_sent = event_type_counts['email_sent'] || 0
        emails_opened = event_type_counts['email_opened'] || 0
        open_rate = emails_sent.zero? ? 0 : (emails_opened.to_f / emails_sent).round(4)
        
        # Unsub stats
        unsubs = event_type_counts['unsub'] || 0
        manual_unsubs = event_type_counts['manual_unsub'] || 0
        total_unsubs = unsubs + manual_unsubs
        unsub_rate = emails_sent.zero? ? 0 : (total_unsubs.to_f / emails_sent).round(4)
        
        # Lead distribution
        leads_by_pipeline = Lead.group(:pipeline).count
        leads_by_source = Lead.group(:source).count.sort_by { |_, v| -v }.first(10)
        leads_by_agent = Lead.joins(:agent).group('agents.name').count.sort_by { |_, v| -v }.first(10)
        
        # Timeline activity (last 30 days)
        thirty_days_ago = 30.days.ago
        recent_events = Event.where('occurred_at >= ?', thirty_days_ago).group(:event_type).count
        
        render json: {
          leads: {
            total: total_leads,
            synced: synced_leads,
            unsynced: total_leads - synced_leads,
            syncedPercentage: total_leads.zero? ? 0 : ((synced_leads.to_f / total_leads) * 100).round(2),
            byPipeline: leads_by_pipeline,
            bySource: leads_by_source.to_h,
            byAgent: leads_by_agent.to_h
          },
          events: {
            total: total_events,
            byType: event_type_counts,
            last30Days: recent_events
          },
          email: {
            sent: emails_sent,
            opened: emails_opened,
            openRate: open_rate,
            openRatePercentage: (open_rate * 100).round(2)
          },
          unsubs: {
            total: total_unsubs,
            auto: unsubs,
            manual: manual_unsubs,
            unsubRate: unsub_rate,
            unsubRatePercentage: (unsub_rate * 100).round(2)
          },
          communication: {
            sms: event_type_counts['sms'] || 0,
            calls: event_type_counts['call'] || 0,
            notes: event_type_counts['note'] || 0,
            tasks: event_type_counts['task'] || 0
          }
        }
      end
    end
  end
end
