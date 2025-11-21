module Api
  module V1
    class LeadsController < BaseController
      # GET /api/v1/leads/:id/profile
      # Returns complete lead profile with all events and stats
      def profile
        lead = Lead.includes(:events, :agent).find(params[:id])
        events = lead.events.order(occurred_at: :desc)

        # Separate events by type
        email_sent_events = events.select { |e| e.event_type == 'email_sent' }
        email_opened_events = events.select { |e| e.event_type == 'email_opened' }
        unsub_events = events.select { |e| e.event_type.in?(%w[unsub manual_unsub]) }

        # Group email_opened events by subject to link them to email_sent
        opened_events = events.select { |e| e.event_type == 'email_opened' }
        opened_by_subject = {}
        
        opened_events.each do |event|
          # Extract subject from rawText
          raw_text = event.metadata['rawText']
          subject = nil
          if raw_text.present?
            lines = raw_text.split("\n")
            subject = lines[1] if lines.length > 1
          end
          subject ||= event.metadata['emailSubject']
          
          if subject.present?
            opened_by_subject[subject] ||= []
            opened_by_subject[subject] << event.occurred_at
          end
        end

        # Group unsub events by occurred_at timestamp (same unsub batch)
        unsub_events = events.select { |e| e.event_type.in?(%w[unsub manual_unsub]) }
        grouped_unsubs = unsub_events.group_by { |e| e.occurred_at.to_s }
        processed_unsub_times = Set.new

        # Build timeline, excluding standalone email_opened events and duplicate unsubs
        timeline = events.reject { |e| e.event_type == 'email_opened' }.filter_map do |event|
          # For unsub events, only process the first one in each timestamp group
          if event.event_type.in?(%w[unsub manual_unsub])
            time_key = event.occurred_at.to_s
            if processed_unsub_times.include?(time_key)
              next nil # Skip duplicate unsubs at same time
            end
            processed_unsub_times.add(time_key)
            
            # Get all unsubs at this timestamp
            same_time_unsubs = grouped_unsubs[time_key] || [event]
            
            # Collect all categories they unsubscribed from
            unsub_categories = same_time_unsubs.map { |e| e.metadata['unsubCategory'] }.compact.uniq
            
            subject = event.metadata.dig('triggerEmail', 'emailSubject')
            email_type = event.metadata.dig('triggerEmail', 'emailType')
            category = Lofty::EmailCategoryClassifier.classify(subject, email_type)
            
            {
              id: event.id,
              type: event.event_type,
              occurredAt: event.occurred_at,
              category: category,
              categoryDisplay: category ? Lofty::EmailCategoryClassifier.category_name(category) : nil,
              opened: false,
              openedAt: [],
              unsubDetails: {
                count: same_time_unsubs.count,
                categories: unsub_categories
              },
              metadata: build_event_metadata(event)
            }
          elsif event.event_type == 'email_sent'
            subject = event.metadata['emailSubject']
            email_type = event.metadata['emailType']
            category = Lofty::EmailCategoryClassifier.classify(subject, email_type)
            
            # Find all opens for this email
            opens = opened_by_subject[subject] || []
            
            {
              id: event.id,
              type: event.event_type,
              occurredAt: event.occurred_at,
              category: category,
              categoryDisplay: category ? Lofty::EmailCategoryClassifier.category_name(category) : nil,
              opened: opens.any?,
              openedAt: opens,
              unsubDetails: nil,
              metadata: build_event_metadata(event)
            }
          else
            # ALL OTHER EVENT TYPES: calls, SMS, notes, pipeline changes, smartplans, etc.
            {
              id: event.id,
              type: event.event_type,
              occurredAt: event.occurred_at,
              category: nil,
              categoryDisplay: nil,
              opened: false,
              openedAt: [],
              unsubDetails: nil,
              fromPipeline: event.from_pipeline,
              toPipeline: event.to_pipeline,
              recordingAvailable: event.recording_available,
              metadata: build_event_metadata(event),
              rawText: event.raw_text
            }
          end
        end

        # Group emails sent by category
        emails_by_category = email_sent_events.group_by do |e|
          subject = e.metadata['emailSubject']
          email_type = e.metadata['emailType']
          Lofty::EmailCategoryClassifier.classify(subject, email_type) || 'uncategorized'
        end.transform_values(&:count)

        category_breakdown = emails_by_category.map do |cat, count|
          {
            category: cat,
            displayName: Lofty::EmailCategoryClassifier.category_name(cat),
            count: count
          }
        end.sort_by { |c| -c[:count] }

        # Calculate stats
        total_sent = email_sent_events.count
        total_opened = email_opened_events.count
        open_rate = total_sent.zero? ? 0 : (total_opened.to_f / total_sent).round(4)
        days_active = lead.reg_date ? (Time.current.to_date - lead.reg_date.to_date).to_i : nil

        render json: {
          lead: {
            id: lead.id,
            name: lead.full_name || [lead.first_name, lead.last_name].compact.join(' '),
            email: lead.email,
            phone: lead.phone,
            source: lead.source,
            pipeline: lead.pipeline,
            segment: lead.segment,
            leadType: lead.lead_type,
            regDate: lead.reg_date,
            agentName: lead.agent&.name,
            loftyLeadId: lead.lofty_lead_id
          },
          stats: {
            totalEmailsSent: total_sent,
            totalEmailsOpened: total_opened,
            openRate: open_rate,
            totalUnsubs: unsub_events.count,
            daysActive: days_active,
            categoryBreakdown: category_breakdown
          },
          timeline: timeline
        }
      end
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

      def build_event_metadata(event)
        base = {
          subject: event.metadata['emailSubject'],
          emailType: event.metadata['emailType'],
          campaignId: event.metadata['campaign_id'],
          unsubCategory: event.metadata['unsubCategory']
        }
        
        # Add call-specific metadata
        if event.event_type == 'call'
          base.merge!({
            call_direction: event.metadata['call_direction'],
            call_duration_seconds: event.metadata['call_duration_seconds'],
            call_result: event.metadata['call_result'],
            call_status: event.metadata['call_status'],
            caller_number: event.metadata['caller_number'],
            call_notes: event.metadata['call_notes'],
            lofty_recording_url: event.metadata['lofty_recording_url']
          })
        end
        
        # Add SMS-specific metadata
        if event.event_type == 'sms'
          base.merge!({
            sms_direction: event.metadata['sms_direction'],
            sms_body: event.metadata['sms_body'],
            virtual_number: event.metadata['virtual_number'],
            delivery_status: event.metadata['delivery_status']
          })
        end
        
        # Add pipeline change metadata
        if event.metadata['activity_type'] == 'pipeline_change'
          base.merge!({
            from: event.metadata['from'],
            to: event.metadata['to'],
            actor: event.metadata['actor']
          })
        end
        
        # Add smartplan metadata
        if event.event_type == 'smartplan'
          base.merge!({
            smartplan_name: event.metadata['smartplan_name'],
            smartplan_action: event.metadata['smartplan_action'],
            smartplan_actor: event.metadata['smartplan_actor'],
            smartplan_step_name: event.metadata['smartplan_step_name'],
            smartplan_step_type: event.metadata['smartplan_step_type']
          })
        end
        
        # Add note metadata
        if event.event_type == 'note'
          base.merge!({
            note_content: event.metadata['note_content'],
            note_author: event.metadata['note_author']
          })
        end
        
        # Add task metadata
        if event.event_type == 'task'
          base.merge!({
            task_title: event.metadata['task_title'],
            task_status: event.metadata['task_status'],
            task_due_date: event.metadata['task_due_date'],
            task_notes: event.metadata['task_notes'],
            task_creator: event.metadata['task_creator']
          })
        end
        
        base
      end

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
