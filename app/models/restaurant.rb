class Restaurant < ApplicationRecord
  belongs_to :user
  has_many :wines, dependent: :destroy

  validates :name, presence: true
  validates :address, presence: true
  validates :proximity_radius_meters, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
end
