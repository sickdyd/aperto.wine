class Restaurant < ApplicationRecord
  include Sluggable

  # Path segments the routes claim before the public menu's `:restaurant_slug`
  # catch-all, so a restaurant carrying one of these as its slug could never be
  # reached. Keep in step with config/routes.rb.
  RESERVED_SLUGS = %w[
    menu t cart orders sign_in sign_up sign_out owner up rails_icons en it
    privacy terms
  ].freeze

  # The range over which a proximity radius actually decides anything. Below 50m
  # the radius is smaller than consumer GPS's own error, so a diner standing at
  # the bar would be turned away as often as not; above 5km it stops being a
  # proximity check and admits most of a city.
  MIN_PROXIMITY_RADIUS_METERS = 50
  MAX_PROXIMITY_RADIUS_METERS = 5000

  belongs_to :user
  has_many :wines, dependent: :destroy
  has_many :wine_lists, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :restaurant_tables, dependent: :destroy

  # The one list the public menu serves. The single-published invariant is
  # enforced by a partial unique index — see WineList#publish!.
  has_one :published_wine_list, -> { where(published: true) },
          class_name: "WineList", inverse_of: :restaurant, dependent: nil

  validates :name, presence: true
  validates :address, presence: true
  validates :proximity_radius_meters,
    numericality: {
      greater_than_or_equal_to: MIN_PROXIMITY_RADIUS_METERS,
      less_than_or_equal_to: MAX_PROXIMITY_RADIUS_METERS
    }
  # A geofence with no origin has nothing to measure against, and the fallback
  # either passes everyone or rejects everyone — both silently. Refuse the
  # combination outright rather than let the owner ship one of those.
  validate :geofence_requires_coordinates

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

  def reserved_slugs
    RESERVED_SLUGS
  end

  private

  # Deliberately not regenerated when the name changes: the slug is the target
  # of every printed QR code, so renaming the restaurant must not silently
  # invalidate them. Owners can still change it by hand.
  def slug_source
    name
  end

  def slug_fallback
    "restaurant-#{SecureRandom.hex(4)}"
  end

  def slug_scope
    Restaurant.all
  end

  def geofence_requires_coordinates
    return unless geofence_enabled?
    return if latitude.present? && longitude.present?

    errors.add(:geofence_enabled, :requires_coordinates)
  end

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
