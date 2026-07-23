require "test_helper"

class RestaurantTest < ActiveSupport::TestCase
  def valid_attributes
    {
      user: users(:owner),
      name: "La Trattoria",
      address: "Via Garibaldi 10, Torino",
      proximity_radius_meters: 150
    }
  end

  # --- Validations ---

  test "creates a valid restaurant" do
    restaurant = Restaurant.new(valid_attributes)
    assert restaurant.valid?
  end

  test "requires name" do
    restaurant = Restaurant.new(valid_attributes.merge(name: ""))
    assert_not restaurant.valid?
    assert restaurant.errors.of_kind?(:name, :blank)
  end

  test "requires address" do
    restaurant = Restaurant.new(valid_attributes.merge(address: ""))
    assert_not restaurant.valid?
    assert restaurant.errors.of_kind?(:address, :blank)
  end

  test "requires proximity_radius_meters greater than 0" do
    restaurant = Restaurant.new(valid_attributes.merge(proximity_radius_meters: 0))
    assert_not restaurant.valid?
    assert restaurant.errors.of_kind?(:proximity_radius_meters, :greater_than)
  end

  test "rejects negative proximity_radius_meters" do
    restaurant = Restaurant.new(valid_attributes.merge(proximity_radius_meters: -10))
    assert_not restaurant.valid?
  end

  test "requires user" do
    restaurant = Restaurant.new(valid_attributes.merge(user: nil))
    assert_not restaurant.valid?
  end

  # --- Associations ---

  test "belongs to user" do
    restaurant = restaurants(:osteria)
    assert_equal users(:owner), restaurant.user
  end

  test "has many wines" do
    restaurant = restaurants(:osteria)
    assert_respond_to restaurant, :wines
    assert restaurant.wines.count > 0
  end

  test "has many orders" do
    restaurant = restaurants(:osteria)
    assert_respond_to restaurant, :orders
  end

  test "destroys dependent wines when deleted" do
    restaurant = Restaurant.create!(valid_attributes)
    restaurant.wines.create!(
      name: "Test Wine",
      color: :red,
      bottle_size_ml: 750,
      available_glasses: 0
    )
    assert_difference "Wine.count", -1 do
      restaurant.destroy
    end
  end

  test "destroys dependent orders when deleted" do
    restaurant = Restaurant.create!(valid_attributes)
    restaurant.orders.create!(
      customer: users(:customer),
      status: :pending,
      total_amount_cents: 0
    )
    assert_difference "Order.count", -1 do
      restaurant.destroy
    end
  end

  # --- Scopes ---

  test "active scope returns only active restaurants" do
    active = Restaurant.active
    assert_includes active, restaurants(:osteria)
    assert_not_includes active, restaurants(:inactive_restaurant)
  end

  test "active scope excludes inactive restaurants" do
    assert_equal false, Restaurant.active.include?(restaurants(:inactive_restaurant))
  end

  # --- Fallback geocoding ---

  test "geocodes on create when address present and coordinates blank" do
    stub_photon([ photon_feature ])

    restaurant = users(:owner).restaurants.create!(name: "Nuova", address: "Via Roma 42, Milano")

    assert_in_delta 45.4642, restaurant.latitude.to_f
    assert_in_delta 9.19, restaurant.longitude.to_f
  end

  test "does not geocode when coordinates are provided" do
    users(:owner).restaurants.create!(
      name: "Nuova", address: "Via Roma 42, Milano", latitude: 45.0, longitude: 9.0
    )

    assert_not_requested :get, PhotonStubs::PHOTON_API
  end

  test "re-geocodes on update when address changes and coordinates were cleared" do
    restaurant = restaurants(:osteria)
    stub_photon([ photon_feature(street: "Via Verdi", housenumber: "7", city: "Torino",
                                 postcode: "10121", lat: 45.0703, lon: 7.6869) ])

    restaurant.update!(address: "Via Verdi 7, Torino", latitude: nil, longitude: nil)

    assert_in_delta 45.0703, restaurant.latitude.to_f
    assert_in_delta 7.6869, restaurant.longitude.to_f
  end

  test "does not geocode when address is unchanged" do
    restaurants(:osteria).update!(description: "Updated")

    assert_not_requested :get, PhotonStubs::PHOTON_API
  end

  test "skips results from countries outside the configured list" do
    stub_photon([ photon_feature(countrycode: "FR", country: "France") ])

    restaurant = users(:owner).restaurants.create!(name: "Nuova", address: "Rue de Rivoli, Paris")

    assert_nil restaurant.latitude
    assert_nil restaurant.longitude
  end

  test "save succeeds when geocoding fails" do
    stub_request(:get, PhotonStubs::PHOTON_API).to_timeout

    restaurant = users(:owner).restaurants.create!(name: "Nuova", address: "Via Roma 42, Milano")

    assert restaurant.persisted?
    assert_nil restaurant.latitude
  end
end
