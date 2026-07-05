class RestaurantTable < ApplicationRecord
  belongs_to :restaurant
  # Keep order history when a table is removed from the room.
  has_many :orders, dependent: :nullify

  has_secure_token :token

  validates :name, presence: true, length: { maximum: 100 },
                   uniqueness: { scope: [ :restaurant_id, :area ], case_sensitive: false }
  validates :area, length: { maximum: 100 }

  scope :active, -> { where(active: true) }
  scope :by_position, -> { order(:area, :position, :name) }

  # Ordered hash of area => tables, for the grouped index and bulk print.
  def self.grouped_by_area
    by_position.group_by(&:area)
  end
end
