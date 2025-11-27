# frozen_string_literal: true

# Generates HausSignals based on event patterns and lead behavior
# Run via: GenerateHausSignals.run
class GenerateHausSignals
  BATCH_SIZE = 1_000

  def self.run
    new.run
  end

  def run
    puts "Generating HausSignals..."
    puts "=" * 80
    
    start_time = Time.current
    
    generate_new_lead_no_human
    generate_automation_only
    generate_warming_up
    generate_idle_clients
    generate_no_next_step
    generate_overdue_tasks
    generate_unreviewed_replies
    
    elapsed = Time.current - start_time
    total_signals = HausSignal.active.count
    
    puts ""
    puts "=" * 80
    puts "Signal generation complete!"
    puts "Total active signals: #{total_signals}"
    puts "Time elapsed: #{elapsed.round(2)}s"
  end

  private

  # =====================================================
  # SIGNAL 1: NEW LEAD - NO HUMAN TOUCH
  # New leads (created <48h ago) with only automated events
  # =====================================================
  def generate_new_lead_no_human
    puts "\n🌱 Generating 'new_lead_no_human' signals..."
    
    # Batch: Get IDs first, then process in chunks
    lead_ids = Lead.where('created_at >= ?', 48.hours.ago).pluck(:id)
    count = 0
    
    lead_ids.each_slice(BATCH_SIZE) do |ids|
      leads = Lead.where(id: ids).includes(:events)
      
      leads.each do |lead|
        events = lead.events.where('occurred_at >= ?', lead.created_at)
        next if events.blank?
        
        manual_count = events.count { |e| !e.auto }
        next unless manual_count.zero?
        
        upsert_signal(
          lead: lead,
          signal_type: 'new_lead_no_human',
          severity: 'high',
          metadata: {
            days_old: ((Time.current - lead.created_at) / 1.day).round(1),
            total_events: events.size,
            auto_events: events.count { |e| e.auto }
          }
        )
        count += 1
      end
    end
    
    puts "  → Created/updated #{count} signals"
  end

  # =====================================================
  # SIGNAL 2: AUTOMATION ONLY
  # Leads with only auto events in last 7 days
  # =====================================================
  def generate_automation_only
    puts "\n🤖 Generating 'automation_only_sequence' signals..."
    
    cutoff = 7.days.ago
    count = 0
    
    # Batch: Get lead IDs with recent events
    lead_ids = Event.where('occurred_at >= ?', cutoff).distinct.pluck(:lead_id)
    
    lead_ids.each_slice(BATCH_SIZE) do |ids|
      leads = Lead.where(id: ids).includes(:events)
      
      leads.each do |lead|
        window_events = lead.events.select { |e| e.occurred_at >= cutoff }
        next if window_events.blank?
        
        manual_count = window_events.count { |e| !e.auto }
        next unless manual_count.zero?
        
        auto_events = window_events.select { |e| e.auto }
        last_manual = lead.events.reject(&:auto).max_by(&:occurred_at)
        
        upsert_signal(
          lead: lead,
          signal_type: 'automation_only_sequence',
          severity: 'medium',
          metadata: {
            auto_events_last_7_days: auto_events.size,
            days_since_last_manual: last_manual ? ((Time.current - last_manual.occurred_at) / 1.day).round(1) : nil,
            last_manual_event_at: last_manual&.occurred_at
          }
        )
        count += 1
      end
    end
    
    puts "  → Created/updated #{count} signals"
  end

  # =====================================================
  # SIGNAL 3: WARMING UP
  # Recent website/email activity showing interest
  # =====================================================
  def generate_warming_up
    puts "\n🔥 Generating 'warming_up_activity' signals..."
    
    cutoff = 3.days.ago
    count = 0
    
    # Batch: Get lead IDs with email/website activity
    lead_ids = Event.where('occurred_at >= ?', cutoff)
                    .where(channel: ['email', 'website'])
                    .distinct
                    .pluck(:lead_id)
    
    lead_ids.each_slice(BATCH_SIZE) do |ids|
      leads = Lead.where(id: ids).includes(:events)
      
      leads.each do |lead|
        engagement_events = lead.events.select do |e|
          e.occurred_at >= cutoff && ['email', 'website'].include?(e.channel)
        end
        
        next if engagement_events.size < 2
        
        # Check for recent manual communication
        recent_manual = lead.events.any? do |e|
          e.occurred_at >= cutoff && e.category == 'communication' && !e.auto
        end
        
        next if recent_manual
        
        upsert_signal(
          lead: lead,
          signal_type: 'warming_up_activity',
          severity: 'medium',
          metadata: {
            engagement_events_count: engagement_events.size,
            email_opens: engagement_events.count { |e| e.channel == 'email' },
            website_visits: engagement_events.count { |e| e.channel == 'website' },
            last_engagement_at: engagement_events.map(&:occurred_at).max
          }
        )
        count += 1
      end
    end
    
    puts "  → Created/updated #{count} signals"
  end

  # =====================================================
  # SIGNAL 4: IDLE CLIENT
  # No events at all in 90+ days
  # =====================================================
  def generate_idle_clients
    puts "\n🕰 Generating 'idle_client' signals..."
    
    cutoff = 90.days.ago
    count = 0
    
    # Batch: Get lead IDs where max event date < cutoff
    lead_ids = Event.group(:lead_id)
                    .having('MAX(occurred_at) < ?', cutoff)
                    .pluck(:lead_id)
    
    lead_ids.each_slice(BATCH_SIZE) do |ids|
      leads = Lead.where(id: ids)
      
      leads.each do |lead|
        last_event_at = Event.where(lead_id: lead.id).maximum(:occurred_at)
        next unless last_event_at && last_event_at < cutoff
        
        upsert_signal(
          lead: lead,
          signal_type: 'idle_client',
          severity: 'medium',
          metadata: {
            days_since_last_activity: ((Time.current - last_event_at) / 1.day).round(0),
            last_event_at: last_event_at
          }
        )
        count += 1
      end
    end
    
    puts "  → Created/updated #{count} signals"
  end

  # =====================================================
  # SIGNAL 5: NO NEXT STEP
  # Recent manual communication but no future task
  # =====================================================
  def generate_no_next_step
    puts "\n🧭 Generating 'no_next_step' signals..."
    
    count = 0
    
    # Find leads with recent manual communication
    Lead.joins(:events)
        .merge(Event.manual_communication)
        .where('events.occurred_at >= ? AND events.occurred_at <= ?', 5.days.ago, 1.day.ago)
        .distinct
        .find_each do |lead|
      
      # Check if they have any future/open tasks
      future_tasks = lead.events.tasks
                         .where("metadata->>'task_status' != ?", 'completed')
                         .where('occurred_at > ?', Time.current)
      
      if future_tasks.none?
        last_manual = lead.events.manual_communication.order(occurred_at: :desc).first
        
        upsert_signal(
          lead: lead,
          signal_type: 'no_next_step',
          severity: 'medium',
          metadata: {
            last_manual_communication_at: last_manual&.occurred_at,
            last_manual_communication_type: last_manual&.event_type,
            days_since_last_manual: last_manual ? (Time.current - last_manual.occurred_at) / 1.day : nil
          }
        )
        count += 1
      end
    end
    
    puts "  → Created/updated #{count} signals"
  end

  # =====================================================
  # SIGNAL 6: OVERDUE TASKS
  # Pending/unknown tasks that are old and may need attention
  # =====================================================
  def generate_overdue_tasks
    puts "\n⏰ Generating 'overdue_tasks' signals..."

    cutoff = Time.current
    count = 0

    # Find leads with pending or unknown tasks that are old
    leads_with_old_tasks = Lead.joins(:events)
                              .merge(Event.where(event_type: 'task'))
                              .merge(Event.where("metadata->>'task_status' IN ('pending', 'unknown')"))
                              .distinct

    leads_with_old_tasks.find_each do |lead|
      # Get pending/unknown tasks for this lead
      old_tasks = lead.events.where(event_type: 'task')
                             .where("metadata->>'task_status' IN ('pending', 'unknown')")
                             .where('occurred_at < ?', cutoff)

      next if old_tasks.empty?

      # Find the oldest pending task
      oldest_task = old_tasks.order(:occurred_at).first
      hours_old = ((cutoff - oldest_task.occurred_at) / 1.hour).floor

      # Skip if not old enough (less than 12 hours)
      next if hours_old < 12

      # Determine severity based on age
      severity = if hours_old > 48 * 24  # 48 days
                   'high'
                 elsif hours_old > 24 * 24  # 24 days
                   'medium'
                 elsif hours_old > 12 * 24  # 12 days
                   'low'
                 else
                   next # Less than 12 days, skip
                 end

      upsert_signal(
        lead: lead,
        signal_type: 'overdue_tasks',
        severity: severity,
        metadata: {
          oldest_task_id: oldest_task.id,
          task_title: oldest_task.metadata['task_title'] || oldest_task.raw_text&.truncate(100),
          task_occurred_at: oldest_task.occurred_at,
          hours_old: hours_old,
          pending_task_count: old_tasks.count
        }
      )
      count += 1
    end

    puts "  → Created/updated #{count} signals"
  end

  # =====================================================
  # SIGNAL 7: UNREVIEWED REPLIES
  # Leads who replied but didn't get human response or follow-up task
  # =====================================================
  def generate_unreviewed_replies
    puts "\n💬 Generating 'unreviewed_replies' signals..."

    cutoff = Time.current
    lookback = 1.week.ago
    window = 2.hours
    count = 0

    # Find leads with recent inbound communication
    inbound_events = Event.where(category: 'communication', direction: 'inbound')
                         .where('occurred_at BETWEEN ? AND ?', lookback, cutoff)
                         .includes(:lead)

    # Group by lead_id and get the latest inbound per lead
    latest_inbound_by_lead = inbound_events.group_by(&:lead_id)
                                          .transform_values { |events| events.max_by(&:occurred_at) }

    latest_inbound_by_lead.each do |lead_id, inbound_event|
      next unless lead_id && inbound_event
      next if cutoff - inbound_event.occurred_at > window

      lead = inbound_event.lead
      next unless lead

      inbound_time = inbound_event.occurred_at

      # Check for manual outbound communication since this inbound
      manual_outbound_exists = Event.where(lead_id: lead_id)
                                   .where(category: 'communication', direction: 'outbound')
                                   .where("metadata->>'communication_kind' = ? OR auto = ?", 'manual', false)
                                   .where('occurred_at > ?', inbound_time)
                                   .exists?

      next if manual_outbound_exists

      # Check for tasks created since this inbound
      followup_task_exists = Event.where(lead_id: lead_id)
                                 .where(event_type: 'task')
                                 .where('occurred_at > ?', inbound_time)
                                 .exists?

      next if followup_task_exists

      # Determine severity based on pipeline stage
      severity = case lead.pipeline_stage
                 when 'hot', 'active'
                   'high'
                 when 'nurture'
                   'medium'
                 else
                   'low'
                 end

      upsert_signal(
        lead: lead,
        signal_type: 'unreviewed_replies',
        severity: severity,
        metadata: {
          inbound_event_id: inbound_event.id,
          inbound_channel: inbound_event.channel,
          inbound_at: inbound_time,
          hours_since_inbound: ((cutoff - inbound_time) / 1.hour).round(1)
        }
      )
      count += 1
    end

    puts "  → Created/updated #{count} signals"
  end

  # =====================================================
  # HELPER: UPSERT SIGNAL
  # =====================================================
  def upsert_signal(lead:, signal_type:, severity:, metadata: {})
    now = Time.current

    # Add standardized metadata fields
    enriched_metadata = enrich_metadata(lead, metadata)

    # Find or initialize by lead + signal_type (unique constraint)
    signal = HausSignal.find_or_initialize_by(
      lead_id: lead.id,
      signal_type: signal_type
    )

    signal.assign_attributes(
      agent_id: lead.agent_id, # Can be nil
      severity: severity,
      metadata: enriched_metadata,
      first_detected_at: signal.first_detected_at || now,
      last_seen_at: now,
      status: 'active'
    )

    signal.save!
  end

  def enrich_metadata(lead, base_metadata)
    now = Time.current

    # Find last manual and any events
    last_manual_event = lead.events.where(auto: false).order(occurred_at: :desc).first
    last_any_event = lead.events.order(occurred_at: :desc).first

    enriched = base_metadata.dup

    # Add standardized fields
    enriched[:last_manual_at] = last_manual_event&.occurred_at&.iso8601
    enriched[:last_any_at] = last_any_event&.occurred_at&.iso8601
    enriched[:days_since_manual] = last_manual_event ? ((now - last_manual_event.occurred_at) / 1.day).round(0) : nil
    enriched[:days_since_any] = last_any_event ? ((now - last_any_event.occurred_at) / 1.day).round(0) : nil

    enriched
  end
end
