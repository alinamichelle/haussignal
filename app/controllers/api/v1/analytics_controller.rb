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

      # GET /api/v1/analytics/sync_status
      # Returns droplet sync monitoring data
      def sync_status
        # Get sync slot distribution
        sync_slot_distribution = Lead.group(:sync_slot).count

        # Calculate recent imports by sync slot (last 24 hours)
        recent_imports = Lead.where('created_at >= ?', 24.hours.ago)
                             .group(:sync_slot)
                             .count

        # Get timeline sync stats by slot
        timeline_sync_stats = Lead.where.not(timeline_synced_at: nil)
                                  .group(:sync_slot)
                                  .count

        # Recent timeline syncs (last hour)
        recent_timeline_syncs = Lead.where('timeline_synced_at >= ?', 1.hour.ago)
                                    .group(:sync_slot)
                                    .count

        # Most recent sync times per slot
        latest_sync_per_slot = Lead.group(:sync_slot)
                                   .maximum(:timeline_synced_at)

        # Most recent imports per slot
        latest_import_per_slot = Lead.group(:sync_slot)
                                     .maximum(:created_at)

        # Build droplet data
        droplets = {}
        (0..3).each do |slot|
          droplets["droplet_#{slot}"] = {
            slot: slot,
            name: "Droplet #{slot}",
            totalLeads: sync_slot_distribution[slot] || 0,
            timelineSynced: timeline_sync_stats[slot] || 0,
            recentImports24h: recent_imports[slot] || 0,
            recentTimelineSync1h: recent_timeline_syncs[slot] || 0,
            lastSyncAt: latest_sync_per_slot[slot],
            lastImportAt: latest_import_per_slot[slot],
            syncProgress: sync_slot_distribution[slot].to_i.zero? ? 0 :
              ((timeline_sync_stats[slot] || 0).to_f / sync_slot_distribution[slot].to_i * 100).round(2)
          }
        end

        # Recent imports timeline (last 100 imports)
        recent_imports_timeline = Lead.order(created_at: :desc)
                                      .limit(100)
                                      .includes(:agent)
                                      .map do |lead|
          {
            id: lead.id,
            loftyLeadId: lead.lofty_lead_id,
            name: lead.full_name || "#{lead.first_name} #{lead.last_name}".strip,
            email: lead.email,
            syncSlot: lead.sync_slot,
            dropletName: "Droplet #{lead.sync_slot}",
            agentName: lead.agent&.name,
            createdAt: lead.created_at,
            timelineSynced: !!lead.timeline_synced_at,
            timelineSyncedAt: lead.timeline_synced_at
          }
        end

        render json: {
          droplets: droplets,
          recentImports: recent_imports_timeline,
          summary: {
            totalLeads: Lead.count,
            totalSynced: Lead.where.not(timeline_synced_at: nil).count,
            last24hImports: Lead.where('created_at >= ?', 24.hours.ago).count,
            last1hTimelineSync: Lead.where('timeline_synced_at >= ?', 1.hour.ago).count
          }
        }
      end
    end
  end
end
