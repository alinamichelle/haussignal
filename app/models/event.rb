class Event < ApplicationRecord
  belongs_to :lead
  belongs_to :agent, optional: true

  enum event_type: {
    unsub: 'unsub',
    manual_unsub: 'manual_unsub',
    email_sent: 'email_sent',
    email_opened: 'email_opened',
    call: 'call',
    email: 'email',
    sms: 'sms',
    smartplan: 'smartplan',
    note: 'note',
    task: 'task',
    alert_view: 'alert_view',
    other: 'other'
  }

  validates :lofty_timeline_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :occurred_at, presence: true

  # =====================================================
  # CANONICAL CATEGORY SCOPES
  # =====================================================
  scope :tasks,           -> { where(category: 'task') }
  scope :communication,   -> { where(category: 'communication') }
  scope :marketing,       -> { where(category: 'marketing') }
  scope :smart_plans,     -> { where(category: 'smart_plan') }
  scope :profile_changes, -> { where(category: 'profile') }
  scope :transactions,    -> { where(category: 'transaction') }
  scope :compliance,      -> { where(category: 'compliance') }
  scope :system_internal, -> { where(category: 'system_internal') }

  # =====================================================
  # AUTO VS MANUAL SCOPES
  # =====================================================
  scope :auto,   -> { where(auto: true) }
  scope :manual, -> { where(auto: false) }

  # =====================================================
  # CHANNEL SCOPES
  # =====================================================
  scope :email,   -> { where(channel: 'email') }
  scope :sms,     -> { where(channel: 'sms') }
  scope :call,    -> { where(channel: 'call') }
  scope :system,  -> { where(channel: 'system') }
  scope :website, -> { where(channel: 'website') }

  # =====================================================
  # DIRECTION SCOPES
  # =====================================================
  scope :inbound,  -> { where(direction: 'inbound') }
  scope :outbound, -> { where(direction: 'outbound') }

  # =====================================================
  # USEFUL COMBINATIONS
  # =====================================================
  scope :manual_communication, -> { communication.manual }
  scope :auto_marketing,       -> { marketing.auto }
  scope :human_touchpoints,    -> { where(category: ['communication', 'task']).manual }
end
