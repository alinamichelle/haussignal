class Lead < ApplicationRecord
  belongs_to :agent, optional: true
  has_many   :events

  validates :lofty_lead_id, presence: true, uniqueness: true
end
