class Event < ApplicationRecord
  belongs_to :lead
  belongs_to :agent, optional: true

  enum event_type: {
    unsub: 'unsub',
    call: 'call',
    email: 'email',
    sms: 'sms',
    smartplan: 'smartplan',
    note: 'note',
    alert_view: 'alert_view',
    other: 'other'
  }

  validates :lofty_timeline_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :occurred_at, presence: true
end
