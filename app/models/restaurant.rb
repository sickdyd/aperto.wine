class Restaurant < ApplicationRecord
  belongs_to :user
  has_many :wines, dependent: :destroy
  has_many :wine_lists, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :restaurant_tables, dependent: :destroy

  validates :name, presence: true
  validates :address, presence: true
  validates :proximity_radius_meters, numericality: { greater_than: 0 }

  # Fallback for owners who typed an address without picking an autocomplete
  # suggestion (picking one submits coordinates, so this never fires then).
  geocoded_by :address do |restaurant, results|
    result = results.find { |r| Geocoding.allowed_country?(r.data.dig("properties", "countrycode")) }
    if result
      restaurant.latitude = result.latitude
      restaurant.longitude = result.longitude
    end
  end
  after_validation :geocode_address, if: :needs_geocoding?

  scope :active, -> { where(active: true) }

  private

  def needs_geocoding?
    address.present? && address_changed? && latitude.blank?
  end

  # Geocoding is best-effort: coordinates stay nil on failure, never
  # blocking the save.
  def geocode_address
    geocode
  rescue StandardError => e
    Rails.logger.warn("Restaurant geocoding failed: #{e.class}: #{e.message}")
  end
end
