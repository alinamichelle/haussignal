class Agent < ApplicationRecord
  has_many :leads
  has_many :events

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
end
