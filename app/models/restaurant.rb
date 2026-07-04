class Restaurant < ApplicationRecord
  belongs_to :user
  has_many :wines, dependent: :destroy
  has_many :wine_lists, dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :address, presence: true
  validates :proximity_radius_meters, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
end
