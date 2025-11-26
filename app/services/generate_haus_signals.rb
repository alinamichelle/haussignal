# frozen_string_literal: true

# Generates HausSignals based on event patterns and lead behavior
# Run via: GenerateHausSignals.run
class GenerateHausSignals
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
    
    # Find leads created in last 48 hours
    new_leads = Lead.where('created_at >= ?', 48.hours.ago)
    
    count = 0
    new_leads.find_each do |lead|
      # Check if they have any events
      total_events = lead.events.count
      next if total_events.zero?
      
      # Check if they have any manual events
      manual_events = lead.events.manual.count
      
      # If they have events but NO manual events, create signal
      if manual_events.zero?
        upsert_signal(
          lead: lead,
          signal_type: 'new_lead_no_human',
          severity: 'high',
          metadata: {
            days_old: (Time.current - lead.created_at) / 1.day,
            total_events: total_events,
            auto_events: lead.events.auto.count
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
    
    count = 0
    
    # Find leads with events in last 7 days
    Lead.joins(:events)
        .where('events.occurred_at >= ?', 7.days.ago)
        .distinct
        .find_each do |lead|
      
      recent_events = lead.events.where('occurred_at >= ?', 7.days.ago)
      manual_count = recent_events.manual.count
      auto_count = recent_events.auto.count
      
      # Only auto events in the window
      if auto_count > 0 && manual_count.zero?
        last_manual = lead.events.manual.order(occurred_at: :desc).first
        days_since_manual = last_manual ? (Time.current - last_manual.occurred_at) / 1.day : nil
        
        upsert_signal(
          lead: lead,
          signal_type: 'automation_only_sequence',
          severity: 'medium',
          metadata: {
            auto_events_last_7_days: auto_count,
            days_since_last_manual: days_since_manual&.round(1),
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
    
    count = 0
    
    # Find leads with recent website or email engagement
    Lead.joins(:events)
        .merge(Event.where(channel: ['email', 'website']))
        .where('events.occurred_at >= ?', 3.days.ago)
        .distinct
        .find_each do |lead|
      
      recent_engagement = lead.events
                              .where(channel: ['email', 'website'])
                              .where('occurred_at >= ?', 3.days.ago)
      
      # Need at least 2 engagement events
      if recent_engagement.count >= 2
        last_manual = lead.events.manual_communication
                          .where('occurred_at >= ?', 3.days.ago)
                          .order(occurred_at: :desc)
                          .first
        
        # Only flag if no recent manual outreach
        if last_manual.nil?
          upsert_signal(
            lead: lead,
            signal_type: 'warming_up_activity',
            severity: 'medium',
            metadata: {
              engagement_events_count: recent_engagement.count,
              email_opens: recent_engagement.email.count,
              website_visits: recent_engagement.website.count,
              last_engagement_at: recent_engagement.maximum(:occurred_at)
            }
          )
          count += 1
        end
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
    
    count = 0
    
    # Find leads where most recent event is >90 days old
    Lead.joins(:events)
        .group('leads.id')
        .having('MAX(events.occurred_at) < ?', 90.days.ago)
        .find_each do |lead|
      
      last_event = lead.events.order(occurred_at: :desc).first
      days_idle = last_event ? (Time.current - last_event.occurred_at) / 1.day : nil
      
      upsert_signal(
        lead: lead,
        signal_type: 'idle_client',
        severity: 'medium',
        metadata: {
          days_since_last_activity: days_idle&.round(0),
          last_event_at: last_event&.occurred_at,
          last_event_type: last_event&.event_type
        }
      )
      count += 1
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
  # HELPER: UPSERT SIGNAL
  # =====================================================
  def upsert_signal(lead:, signal_type:, severity:, metadata: {})
    now = Time.current
    
    # Find or initialize by lead + signal_type (unique constraint)
    signal = HausSignal.find_or_initialize_by(
      lead_id: lead.id,
      signal_type: signal_type
    )
    
    signal.assign_attributes(
      agent_id: lead.agent_id, # Can be nil
      severity: severity,
      metadata: metadata,
      first_detected_at: signal.first_detected_at || now,
      last_seen_at: now,
      status: 'active'
    )
    
    signal.save!
  end
end
