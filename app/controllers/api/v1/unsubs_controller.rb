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
        unsubs = unsub_scope

        # Count unique leads who unsubscribed, not total unsub events
        total_unsubs = unsubs.distinct.count(:lead_id)

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
        unsubs = unsub_scope

        # Unsubs over time (line chart) - count distinct leads per day
        over_time = unsubs
          .group("DATE(occurred_at)")
          .order("DATE(occurred_at)")
          .distinct
          .count(:lead_id)
          .map { |date, count| { date: date.to_s, unsubs: count } }

        # Unsubs by agent (bar chart) - count distinct leads per agent
        by_agent = unsubs
          .joins(:agent)
          .group('agents.id', 'agents.name')
          .distinct
          .count(:lead_id)
          .map { |(id, name), count| { agentId: id, agentName: name, unsubs: count } }

        # Unsubs by source (pie chart) - count distinct leads per source
        by_source = unsubs
          .joins(:lead)
          .group('leads.source')
          .distinct
          .count(:lead_id)
          .map { |source, count| { source: source || 'Unknown', unsubs: count } }

        # Pipeline at unsub (stacked bar chart) - count distinct leads
        pipeline_at_unsub = unsubs
          .joins(:lead)
          .group('leads.pipeline', "metadata->>'emailType'")
          .distinct
          .count(:lead_id)

        pipeline_data = pipeline_at_unsub.each_with_object(Hash.new { |h,k| h[k] = { 'mass' => 0, 'manual' => 0, 'auto' => 0 } }) do |((pipeline, email_type), count), h|
          t = email_type || 'auto'
          h[pipeline || 'Unknown'][t] += count
        end.map do |pipeline, counts|
          { stage: pipeline, mass: counts['mass'], manual: counts['manual'], auto: counts['auto'] }
        end

        # Time to unsub buckets (histogram) - count unique leads
        time_buckets = Hash.new(0)
        seen_leads = Set.new
        unsubs.includes(:lead).order(:lead_id, :occurred_at).find_each do |unsub|
          next if seen_leads.include?(unsub.lead_id)
          next unless unsub.lead&.reg_date
          
          seen_leads.add(unsub.lead_id)
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
        unsubs = unsub_scope
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

          # Count distinct leads who unsubscribed from this campaign
          # Match by campaign_id if available, otherwise by trigger email subject
          unsub_count = if cid != 'unknown'
            unsubs.where("metadata->>'campaign_id' = ?", cid).distinct.count(:lead_id)
          else
            # Match by trigger email subject in metadata
            unsubs.where("metadata->'triggerEmail'->>'emailSubject' = ?", subject).distinct.count(:lead_id)
          end
          
          # Match opens by campaign_id if available, otherwise by subject in rawText
          open_count = if cid != 'unknown'
            opens.where("metadata->>'campaign_id' = ?", cid).count
          else
            # For emails without campaign_id, match by checking if subject is in rawText
            # Opens have format: "[Type] Name opened email\nActual Subject\nDate"
            opens.where("(metadata->>'rawText') LIKE ?", "%\n#{subject.gsub("'", "''")}\n%").count
          end

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

      # GET /api/v1/unsubs/analytics
      # Returns unsubs and email analytics by year and month
      def analytics
        # Get all unsubs (no filters applied for analytics)
        all_unsubs = Event.where(event_type: UNSUB_EVENT_TYPES)
        all_emails_sent = Event.where(event_type: EMAIL_SENT_TYPES)

        # Unsubs by year - count distinct leads
        unsubs_by_year = all_unsubs
          .group("EXTRACT(YEAR FROM occurred_at)")
          .distinct
          .count(:lead_id)
          .transform_keys(&:to_i)
          .sort
          .map { |year, count| { year: year, count: count } }

        # Unsubs by month (last 24 months)
        unsubs_by_month = all_unsubs
          .where('occurred_at >= ?', 24.months.ago)
          .group("DATE_TRUNC('month', occurred_at)")
          .distinct
          .count(:lead_id)
          .sort
          .map { |month, count| { month: month.to_date.to_s, count: count } }

        # Emails sent by year
        emails_by_year = all_emails_sent
          .group("EXTRACT(YEAR FROM occurred_at)")
          .count
          .transform_keys(&:to_i)
          .sort
          .map { |year, count| { year: year, count: count } }

        # Emails sent by month (last 24 months) - broken down by category
        # Group by month and classify by category
        emails_by_month_category = {}
        
        Event.where(event_type: 'email_sent')
          .where('occurred_at >= ?', 24.months.ago)
          .find_each do |event|
          month = event.occurred_at.beginning_of_month.to_date.to_s
          subject = event.metadata['emailSubject']
          email_type = event.metadata['emailType']
          category = Lofty::EmailCategoryClassifier.classify(subject, email_type) || 'uncategorized'
          
          emails_by_month_category[month] ||= Hash.new(0)
          emails_by_month_category[month][category] += 1
        end

        # Get all unique categories
        all_categories = emails_by_month_category.values.flat_map(&:keys).uniq.sort

        # Build final array with all categories per month
        emails_by_month = emails_by_month_category.keys.sort.map do |month|
          row = { month: month }
          all_categories.each do |category|
            row[category] = emails_by_month_category[month][category] || 0
          end
          row
        end

        render json: {
          unsubsByYear: unsubs_by_year,
          unsubsByMonth: unsubs_by_month,
          emailsSentByYear: emails_by_year,
          emailsSentByMonth: emails_by_month,
          emailCategories: all_categories.map { |cat| { key: cat, name: Lofty::EmailCategoryClassifier.category_name(cat) } }
        }
      end

      # GET /api/v1/unsubs/leads
      # Returns all unsubscribed leads grouped by trigger email category
      def leads
        unsubs = unsub_scope

        # Classify each unsub event by its trigger email category
        category_counts = Hash.new(0)
        lead_seen = Set.new
        
        unsubs.includes(:lead).find_each do |unsub|
          next if lead_seen.include?(unsub.lead_id)
          
          # Manual unsubs get their own category
          if unsub.event_type == 'manual_unsub'
            category = 'manual_unsub'
          else
            # Get trigger email subject and type for auto unsubs
            subject = unsub.metadata.dig('triggerEmail', 'emailSubject')
            email_type = unsub.metadata.dig('triggerEmail', 'emailType')
            category = Lofty::EmailCategoryClassifier.classify(subject, email_type) || 'uncategorized'
          end
          
          category_counts[category] += 1
          lead_seen.add(unsub.lead_id)
        end

        # Map to friendly display names and sort by count
        stats = category_counts.map do |category, count|
          { 
            category: category,
            displayName: Lofty::EmailCategoryClassifier.category_name(category),
            count: count 
          }
        end.sort_by { |s| -s[:count] }

        # Get all unique unsubscribed leads with their unsub events
        # Group by lead_id and collect all categories they unsubscribed from
        lead_unsubs = unsubs
          .includes(:lead, :agent)
          .order(:lead_id, occurred_at: :asc)
          .group_by(&:lead_id)

        leads_list = lead_unsubs.map do |lead_id, events|
          first_event = events.first
          lead = first_event.lead
          
          # Classify all trigger email categories for this lead
          categories = events.map do |e|
            if e.event_type == 'manual_unsub'
              'manual_unsub'
            else
              subject = e.metadata.dig('triggerEmail', 'emailSubject')
              email_type = e.metadata.dig('triggerEmail', 'emailType')
              Lofty::EmailCategoryClassifier.classify(subject, email_type) || 'uncategorized'
            end
          end.uniq
          
          {
            leadId: lead.id,
            name: lead.full_name || [lead.first_name, lead.last_name].compact.join(' '),
            email: lead.email,
            source: lead.source,
            pipeline: lead.pipeline,
            agentName: lead.agent&.name,
            emailCategories: categories,
            firstUnsubAt: events.first.occurred_at,
            lastUnsubAt: events.last.occurred_at,
            totalUnsubEvents: events.size,
            regDate: lead.reg_date
          }
        end.sort_by { |l| l[:lastUnsubAt] }.reverse

        render json: {
          stats: stats,
          leads: leads_list,
          totalLeads: leads_list.size
        }
      end

      # GET /api/v1/unsubs/campaigns/:id
      # Returns detailed campaign metrics and list of unsubscribers
      def campaign
        cid = params[:id]

        sent   = email_sent_scope.where("metadata->>'campaign_id' = ?", cid)
        unsubs = unsub_scope.where("metadata->>'campaign_id' = ?", cid)
        opens  = scoped_events.where(event_type: EMAIL_OPENED_TYPES)
                              .where("metadata->>'campaign_id' = ?", cid)

        subject     = sent.pick(Arel.sql("metadata->>'emailSubject'")) || '(No subject)'
        email_type  = sent.pick(Arel.sql("metadata->>'emailType'")) || 'auto'
        sent_count  = sent.count
        open_count  = opens.count
        # Count distinct leads who unsubscribed
        unsub_count = unsubs.distinct.count(:lead_id)

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

        # Build unsubscriber list with engagement data - show unique leads only
        # Group by lead_id and take the first unsub event per lead
        unsubscriber_events = unsubs
          .includes(:lead, :agent)
          .order(:lead_id, occurred_at: :asc)
          .group_by(&:lead_id)
          .map { |lead_id, events| events.first }
          .sort_by(&:occurred_at)
          .reverse
        
        unsubscribers = unsubscriber_events.map do |e|
            lead = e.lead
            {
              leadId: lead.id,
              name: lead.full_name || [lead.first_name, lead.last_name].compact.join(' '),
              email: lead.email,
              agentName: lead.agent&.name,
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

      # Build unsub event scope WITHOUT email_type filter
      # A lead counts as unsubscribed if they have ANY unsub event,
      # regardless of what type of email they unsubscribed from
      def unsub_scope
        scope = Event.where(occurred_at: parsed_range)
        scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
        scope = scope.joins(:lead).where(leads: { pipeline: params[:pipeline] }) if params[:pipeline].present?
        scope.where(event_type: UNSUB_EVENT_TYPES)
      end

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
