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
      # Returns droplet sync monitoring data with optional filtering
      def sync_status
        # Apply filters to lead scope
        filtered_scope = filtered_lead_scope

        # Get sync slot distribution
        sync_slot_distribution = filtered_scope.group(:sync_slot).count

        # Calculate recent imports by sync slot (last 24 hours)
        recent_imports = filtered_scope.where('created_at >= ?', 24.hours.ago)
                                      .group(:sync_slot)
                                      .count

        # Get timeline sync stats by slot
        timeline_sync_stats = filtered_scope.where.not(timeline_synced_at: nil)
                                           .group(:sync_slot)
                                           .count

        # Recent timeline syncs (last hour)
        recent_timeline_syncs = filtered_scope.where('timeline_synced_at >= ?', 1.hour.ago)
                                             .group(:sync_slot)
                                             .count

        # Most recent sync times per slot
        latest_sync_per_slot = filtered_scope.group(:sync_slot)
                                            .maximum(:timeline_synced_at)

        # Most recent imports per slot
        latest_import_per_slot = filtered_scope.group(:sync_slot)
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

        # Get recent imports timeline - order by most recently synced/imported first
        # Prioritize timeline_synced_at if available, otherwise use created_at
        recent_imports_timeline = filtered_scope.includes(:agent)
                                               .order(Arel.sql('COALESCE(timeline_synced_at, created_at) DESC'))
                                               .limit(100)
                                               .map do |lead|
          {
            id: lead.id,
            loftyLeadId: lead.lofty_lead_id,
            name: lead.full_name || "#{lead.first_name} #{lead.last_name}".strip,
            email: lead.email,
            source: lead.source,
            pipeline: lead.pipeline,
            syncSlot: lead.sync_slot,
            dropletName: "Droplet #{lead.sync_slot}",
            agentName: lead.agent&.name,
            agentId: lead.agent_id,
            createdAt: lead.created_at,
            timelineSynced: !!lead.timeline_synced_at,
            timelineSyncedAt: lead.timeline_synced_at,
            regDate: lead.reg_date,
            lastActivityAt: lead.timeline_synced_at || lead.created_at
          }
        end

        # Get filter options for frontend
        filter_options = {
          agents: Lead.joins(:agent).distinct.pluck('agents.id', 'agents.name')
                     .map { |id, name| { id: id, name: name } }
                     .sort_by { |agent| agent[:name] },
          pipelines: Lead.distinct.pluck(:pipeline).compact.sort,
          sources: Lead.distinct.pluck(:source).compact.sort,
          syncSlots: (0..3).to_a
        }

        render json: {
          droplets: droplets,
          recentImports: recent_imports_timeline,
          filterOptions: filter_options,
          appliedFilters: {
            agentId: params[:agent_id],
            pipeline: params[:pipeline],
            source: params[:source],
            syncSlot: params[:sync_slot]
          },
          summary: {
            totalLeads: filtered_scope.count,
            totalSynced: filtered_scope.where.not(timeline_synced_at: nil).count,
            last24hImports: filtered_scope.where('created_at >= ?', 24.hours.ago).count,
            last1hTimelineSync: filtered_scope.where('timeline_synced_at >= ?', 1.hour.ago).count
          }
        }
      end

      # GET /api/v1/analytics/event_distribution
      # Debug endpoint to check which leads have zero events
      def event_distribution
        # Count leads with zero events
        leads_with_zero_events = Lead.left_joins(:events)
                                    .group('leads.id')
                                    .having('COUNT(events.id) = 0')
                                    .count.size

        # Count leads with some events
        leads_with_events = Lead.joins(:events)
                               .group('leads.id')
                               .having('COUNT(events.id) > 0')
                               .count.size

        # Get sample of leads with zero events that are marked as synced
        false_synced_leads = Lead.left_joins(:events)
                                .where.not(timeline_synced_at: nil)
                                .group('leads.id')
                                .having('COUNT(events.id) = 0')
                                .limit(10)
                                .pluck('leads.id', 'leads.lofty_lead_id', 'leads.full_name', 'leads.timeline_synced_at')

        render json: {
          totalLeads: Lead.count,
          leadsWithZeroEvents: leads_with_zero_events,
          leadsWithEvents: leads_with_events,
          markedSyncedButZeroEvents: false_synced_leads.size,
          sampleFalseSynced: false_synced_leads.map do |id, lofty_id, name, synced_at|
            {
              id: id,
              loftyLeadId: lofty_id,
              name: name,
              syncedAt: synced_at
            }
          end
        }
      end

      private

      # Build filtered lead scope based on query parameters
      def filtered_lead_scope
        scope = Lead.all
        scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
        scope = scope.where(pipeline: params[:pipeline]) if params[:pipeline].present?
        scope = scope.where(source: params[:source]) if params[:source].present?
        scope = scope.where(sync_slot: params[:sync_slot]) if params[:sync_slot].present?
        scope
      end
    end
  end
end
