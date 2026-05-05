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
    assert_includes restaurant.errors[:name], "can't be blank"
  end

  test "requires address" do
    restaurant = Restaurant.new(valid_attributes.merge(address: ""))
    assert_not restaurant.valid?
    assert_includes restaurant.errors[:address], "can't be blank"
  end

  test "requires proximity_radius_meters greater than 0" do
    restaurant = Restaurant.new(valid_attributes.merge(proximity_radius_meters: 0))
    assert_not restaurant.valid?
    assert_includes restaurant.errors[:proximity_radius_meters], "must be greater than 0"
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
end
