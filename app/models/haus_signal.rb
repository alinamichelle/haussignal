class HausSignal < ApplicationRecord
  belongs_to :lead
  belongs_to :agent, optional: true

  enum :severity, {
    low: 'low',
    medium: 'medium',
    high: 'high',
    critical: 'critical'
  }, validate: true

  enum :status, {
    active: 'active',
    resolved: 'resolved',
    dismissed: 'dismissed'
  }, validate: true

  ALLOWED_SIGNAL_TYPES = %w[
    new_lead_no_human
    automation_only_sequence
    warming_up_activity
    idle_client
    no_next_step
    overdue_tasks
    unreviewed_replies
  ].freeze

  validates :severity, inclusion: { in: %w[low medium high] }
  validates :signal_type, inclusion: { in: ALLOWED_SIGNAL_TYPES }
  validate :ensure_metadata_exists
  validates :first_detected_at, presence: true
  validates :last_seen_at, presence: true

  before_validation :ensure_metadata_hash
  after_initialize :set_default_metadata

  scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
  scope :active, -> { where(status: 'active') }

  # =====================================================
  # SIGNAL DEFINITIONS REGISTRY
  # =====================================================
  SIGNAL_DEFINITIONS = {
    'new_lead_no_human' => {
      label: 'New Lead – No Human Touch',
      description: 'This new lead has only received automated messages. No human has reached out yet.',
      default_severity: 'high',
      icon: '🌱'
    },
    'automation_only_sequence' => {
      label: 'Automation Only',
      description: "This contact is in automation only. They haven't received a human touch recently.",
      default_severity: 'medium',
      icon: '🤖'
    },
    'warming_up_activity' => {
      label: 'Warming Up',
      description: "This contact has been opening emails or visiting your site. They're showing interest.",
      default_severity: 'medium',
      icon: '🔥'
    },
    'high_intent_spike' => {
      label: 'High Intent Activity',
      description: 'This contact has a spike in activity across multiple touchpoints in a short time.',
      default_severity: 'high',
      icon: '🎯'
    },
    'idle_client' => {
      label: 'Idle Client',
      description: 'No activity with this contact for a while. Time to check in.',
      default_severity: 'medium',
      icon: '🕰'
    },
    'overdue_tasks' => {
      label: 'Overdue Tasks',
      description: 'This contact has open tasks that are past due.',
      default_severity: 'medium',
      icon: '📋'
    },
    'stalled_deal' => {
      label: 'Stalled Deal',
      description: "This active deal hasn't had meaningful activity in a while.",
      default_severity: 'high',
      icon: '⏸'
    },
    'no_next_step' => {
      label: 'No Next Step',
      description: "You recently spoke with this contact, but there's no next task scheduled.",
      default_severity: 'medium',
      icon: '🧭'
    },
    'unreviewed_replies' => {
      label: 'Unreviewed Replies',
      description: 'This contact replied but has not received a human response or follow-up task.',
      default_severity: 'medium',
      icon: '💬'
    }
  }.freeze

  # =====================================================
  # UI HELPER METHODS
  # =====================================================

  def ui_label
    SIGNAL_DEFINITIONS.dig(signal_type, :label) || signal_type.humanize
  end

  def ui_description
    case signal_type
    when 'new_lead_no_human'
      days = metadata['days_old']
      "New lead (#{days} days old) with no human touches"
    when 'automation_only_sequence'
      auto_count = metadata['auto_events_last_7_days'] || 0
      days = metadata['days_since_last_manual']
      if days
        "#{auto_count} auto touches, 0 manual in #{days.round(0)} days"
      else
        "#{auto_count} auto touches, no manual touches yet"
      end
    when 'warming_up_activity'
      email_count = metadata['email_opens'] || 0
      website_count = metadata['website_visits'] || 0
      "#{email_count + website_count} engagement events in 3 days"
    when 'idle_client'
      days = metadata['days_since_last_activity'] || 0
      "No touches in #{days} days"
    when 'overdue_tasks'
      task_count = metadata['overdue_task_count'] || 1
      oldest_days = metadata['oldest_overdue_days'] || 0
      "#{task_count} overdue task#{task_count == 1 ? '' : 's'} (#{oldest_days} days old)"
    when 'unreviewed_replies'
      days = metadata['days_since_inbound'] || 0
      "Inbound reply #{days} days ago, no human follow-up"
    when 'no_next_step'
      days = metadata['days_since_last_manual']
      if days
        "Manual touch #{days.round(0)} days ago, no next step"
      else
        "Recent manual touch, no next step scheduled"
      end
    else
      SIGNAL_DEFINITIONS.dig(signal_type, :description) || ''
    end
  end

  def ui_icon
    SIGNAL_DEFINITIONS.dig(signal_type, :icon) || '🔔'
  end

  def default_severity_for_type
    SIGNAL_DEFINITIONS.dig(signal_type, :default_severity) || 'medium'
  end

  private

  def ensure_metadata_hash
    self.metadata = {} if metadata.nil?
  end

  def set_default_metadata
    self.metadata ||= {} if new_record?
  end

  def ensure_metadata_exists
    errors.add(:metadata, "must be present") if metadata.nil?
  end
end
