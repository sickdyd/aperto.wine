class User < ApplicationRecord
  has_secure_password

  has_many :restaurants, dependent: :destroy

  enum :role, { customer: 0, owner: 1, admin: 2 }

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true
  validates :password, length: { minimum: 8 }, if: -> { password_digest_changed? || new_record? }

  def confirmed?
    confirmed_at.present?
  end

  def confirm!
    update!(confirmed_at: Time.current)
  end
end
