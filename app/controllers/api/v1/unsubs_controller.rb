module Api
  module V1
    class UnsubsController < BaseController
      # Event types used in queries
      UNSUB_EVENT_TYPES  = %w[unsub manual_unsub].freeze
      EMAIL_SENT_TYPES   = %w[email_sent].freeze
      EMAIL_OPENED_TYPES = %w[email_opened].freeze

      # GET /api/v1/unsubs/summary
      # Returns KPI metrics for the unsubscribe dashboard
      def summary
        unsubs = scoped_events.where(event_type: UNSUB_EVENT_TYPES)

        total_unsubs = unsubs.count

        total_emails_sent = email_sent_scope.count
        unsub_rate        = total_emails_sent.zero? ? 0 : total_unsubs.to_f / total_emails_sent

        avg_emails_before_unsub = average_emails_before_unsub(unsubs)
        avg_days_to_unsub       = average_days_to_unsub(unsubs)
        avg_open_rate_before    = average_open_rate_before_unsub(unsubs)

        # Find top trigger email
        top_trigger = unsubs
          .group("metadata->>'campaign_id'", "metadata->>'emailSubject'")
          .order(Arel.sql('COUNT(*) DESC'))
          .limit(1)
          .pluck(Arel.sql("metadata->>'campaign_id'"), Arel.sql("metadata->>'emailSubject'"), Arel.sql('COUNT(*)'))
          .first

        render json: {
          totalUnsubs: total_unsubs,
          unsubRate: unsub_rate.round(4),
          avgEmailsBeforeUnsub: avg_emails_before_unsub.round(2),
          avgDaysToUnsub: avg_days_to_unsub.round(1),
          avgOpenRateBeforeUnsub: avg_open_rate_before.round(4),
          topTriggerEmail: top_trigger && {
            campaignId: top_trigger[0],
            subject:    top_trigger[1],
            unsubs:     top_trigger[2]
          }
        }
      end

      # GET /api/v1/unsubs/series
      # Returns time series data for all charts
      def series
        unsubs = scoped_events.where(event_type: UNSUB_EVENT_TYPES)

        # Unsubs over time (line chart)
        over_time = unsubs
          .group("DATE(occurred_at)")
          .order("DATE(occurred_at)")
          .count
          .map { |date, count| { date: date.to_s, unsubs: count } }

        # Unsubs by agent (bar chart)
        by_agent = unsubs
          .joins(:agent)
          .group('agents.id', 'agents.name')
          .count
          .map { |(id, name), count| { agentId: id, agentName: name, unsubs: count } }

        # Unsubs by source (pie chart)
        by_source = unsubs
          .joins(:lead)
          .group('leads.source')
          .count
          .map { |source, count| { source: source || 'Unknown', unsubs: count } }

        # Pipeline at unsub (stacked bar chart)
        pipeline_at_unsub = unsubs
          .joins(:lead)
          .group('leads.pipeline', "metadata->>'emailType'")
          .count

        pipeline_data = pipeline_at_unsub.each_with_object(Hash.new { |h,k| h[k] = { 'mass' => 0, 'manual' => 0, 'auto' => 0 } }) do |((pipeline, email_type), count), h|
          t = email_type || 'auto'
          h[pipeline || 'Unknown'][t] += count
        end.map do |pipeline, counts|
          { stage: pipeline, mass: counts['mass'], manual: counts['manual'], auto: counts['auto'] }
        end

        # Time to unsub buckets (histogram)
        time_buckets = Hash.new(0)
        unsubs.includes(:lead).find_each do |unsub|
          next unless unsub.lead&.reg_date

          days = ((unsub.occurred_at.to_date - unsub.lead.reg_date.to_date)).to_i
          bucket =
            case days
            when 0..7    then '0-7'
            when 8..30   then '8-30'
            when 31..90  then '31-90'
            when 91..180 then '91-180'
            else '181+'
            end
          time_buckets[bucket] += 1
        end

        render json: {
          overTime: over_time,
          byAgent: by_agent,
          bySource: by_source,
          pipelineAtUnsub: pipeline_data,
          timeToUnsubBuckets: time_buckets.map { |bucket, count| { bucket: bucket, count: count } }
        }
      end

      # GET /api/v1/unsubs/campaigns
      # Returns list of all campaigns with performance metrics
      def campaigns
        sent   = email_sent_scope
        unsubs = scoped_events.where(event_type: UNSUB_EVENT_TYPES)
        opens  = scoped_events.where(event_type: EMAIL_OPENED_TYPES)

        # Group by campaign_id from metadata
        sent_counts = sent
          .group("metadata->>'campaign_id'", "metadata->>'emailSubject'", "metadata->>'emailType'")
          .select("metadata->>'campaign_id' AS campaign_id,
                   metadata->>'emailSubject' AS subject,
                   metadata->>'emailType' AS email_type,
                   MIN(occurred_at) AS first_sent_at,
                   MAX(occurred_at) AS last_sent_at,
                   COUNT(*) AS total_sent")

        campaign_rows = sent_counts.map do |row|
          cid        = row.campaign_id || 'unknown'
          subject    = row.subject || '(No subject)'
          email_type = row.email_type || 'auto'
          sent_count = row.total_sent.to_i

          unsub_count = unsubs.where("metadata->>'campaign_id' = ?", cid).count
          open_count  = opens.where("metadata->>'campaign_id' = ?", cid).count

          {
            id: cid,
            subject: subject,
            type: email_type,
            totalSent: sent_count,
            totalOpened: open_count,
            totalUnsubs: unsub_count,
            unsubRate: sent_count.zero? ? 0 : (unsub_count.to_f / sent_count).round(4),
            openRate: sent_count.zero? ? 0 : (open_count.to_f / sent_count).round(4),
            firstSentAt: row.first_sent_at,
            lastSentAt: row.last_sent_at
          }
        end

        render json: campaign_rows
      end

      # GET /api/v1/unsubs/campaigns/:id
      # Returns detailed campaign metrics and list of unsubscribers
      def campaign
        cid = params[:id]

        sent   = email_sent_scope.where("metadata->>'campaign_id' = ?", cid)
        unsubs = scoped_events.where(event_type: UNSUB_EVENT_TYPES)
                              .where("metadata->>'campaign_id' = ?", cid)
        opens  = scoped_events.where(event_type: EMAIL_OPENED_TYPES)
                              .where("metadata->>'campaign_id' = ?", cid)

        subject     = sent.pick("metadata->>'emailSubject'") || '(No subject)'
        email_type  = sent.pick("metadata->>'emailType'") || 'auto'
        sent_count  = sent.count
        open_count  = opens.count
        unsub_count = unsubs.count

        campaign_payload = {
          id: cid,
          subject: subject,
          type: email_type,
          totalSent: sent_count,
          totalOpened: open_count,
          totalUnsubs: unsub_count,
          unsubRate: sent_count.zero? ? 0 : (unsub_count.to_f / sent_count).round(4),
          openRate: sent_count.zero? ? 0 : (open_count.to_f / sent_count).round(4),
          sentFrom: sent.minimum(:occurred_at),
          sentTo: sent.maximum(:occurred_at)
        }

        # Build unsubscriber list with engagement data
        unsubscribers = unsubs
          .includes(:lead, :agent)
          .order(occurred_at: :desc)
          .map do |e|
            lead = e.lead
            {
              leadId: lead.id,
              name: lead.full_name || [lead.first_name, lead.last_name].compact.join(' '),
              email: lead.email,
              agentName: e.agent&.name,
              source: lead.source,
              pipeline: lead.pipeline,
              unsubscribedAt: e.occurred_at,
              emailsSentBefore: email_sent_scope.where(lead_id: lead.id)
                                                .where('occurred_at < ?', e.occurred_at).count,
              emailsOpenedBefore: scoped_events.where(lead_id: lead.id, event_type: EMAIL_OPENED_TYPES)
                                               .where('occurred_at < ?', e.occurred_at).count,
              daysActive: lead.reg_date ? (e.occurred_at.to_date - lead.reg_date.to_date).to_i : nil
            }
          end

        render json: { campaign: campaign_payload, unsubscribers: unsubscribers }
      end

      private

      def email_sent_scope
        scoped_events.where(event_type: EMAIL_SENT_TYPES)
      end

      # NOTE: N+1 style but acceptable for current volumes; optimize later if needed.
      def average_emails_before_unsub(unsubs)
        return 0 if unsubs.empty?

        total = 0
        unsubs.includes(:lead).find_each do |u|
          total += email_sent_scope.where(lead_id: u.lead_id)
                                   .where('occurred_at <= ?', u.occurred_at)
                                   .count
        end
        total.to_f / unsubs.count
      end

      def average_days_to_unsub(unsubs)
        values = unsubs.includes(:lead).map do |u|
          next unless u.lead&.reg_date
          (u.occurred_at.to_date - u.lead.reg_date.to_date).to_i
        end.compact
        return 0 if values.empty?
        values.sum.to_f / values.size
      end

      def average_open_rate_before_unsub(unsubs)
        rates = unsubs.includes(:lead).map do |u|
          sent = email_sent_scope.where(lead_id: u.lead_id)
                                 .where('occurred_at <= ?', u.occurred_at)
          sent_count = sent.count
          next if sent_count.zero?
          opens = scoped_events.where(lead_id: u.lead_id, event_type: EMAIL_OPENED_TYPES)
                               .where('occurred_at <= ?', u.occurred_at)
                               .count
          opens.to_f / sent_count
        end.compact
        return 0 if rates.empty?
        rates.sum / rates.size
      end
    end
  end
end
