class WineList < ApplicationRecord
  belongs_to :restaurant
  has_many :wine_list_items, dependent: :destroy
  has_many :wines, through: :wine_list_items

  validates :name, presence: true, length: { maximum: 100 }
  validates :season, length: { maximum: 50 }

  scope :active, -> { where(active: true) }
  scope :by_position, -> { order(:position, :name) }
end
