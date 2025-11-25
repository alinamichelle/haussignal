class User < ApplicationRecord
  has_secure_password

  enum role: {
    admin: 0,
    agent: 1,
    viewer: 2
  }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true

  # Default to active
  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.active = true if active.nil?
  end
end
