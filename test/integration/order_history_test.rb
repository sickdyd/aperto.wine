require "test_helper"

class OrderHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
  end

  def add_barolo_to_cart(restaurant: @osteria, quantity: 1)
    post cart_items_path(restaurant_id: restaurant), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: quantity }
  end

  def place_order(restaurant: @osteria, guest_name: "Jane")
    add_barolo_to_cart(restaurant: restaurant)
    post orders_path(restaurant_id: restaurant), params: { guest_name: guest_name }
    Order.order(:created_at).last
  end

  test "placing an order records it, and it appears on the device's index" do
    order = place_order

    get orders_path(restaurant_id: @osteria)
    assert_response :success
    assert_match order.public_token, response.body
  end

  test "two orders both appear on the index, newest first" do
    first = place_order(guest_name: "First Diner")
    second = place_order(guest_name: "Second Diner")

    get orders_path(restaurant_id: @osteria)
    assert_response :success
    assert_operator response.body.index(second.public_token), :<, response.body.index(first.public_token)
  end

  test "a fresh device's index renders successfully and lists nothing" do
    get orders_path(restaurant_id: @osteria)
    assert_response :success
    # No order_tokens cookie was ever set, so none of this restaurant's
    # existing orders — fixtures or otherwise — should resolve for us.
    assert_no_match orders(:pending_order).public_token, response.body
    assert_no_match orders(:approved_order).public_token, response.body
  end

  test "an order placed at restaurant A does not appear on restaurant B's index" do
    order = place_order(restaurant: @osteria)

    get orders_path(restaurant_id: @trattoria)
    assert_response :success
    assert_no_match order.public_token, response.body
  end

  test "the index for an inactive restaurant 404s" do
    inactive = restaurants(:inactive_restaurant)
    get orders_path(restaurant_id: inactive)
    assert_response :not_found
  end

  test "GET /orders/:public_token does not add the order to the device's history" do
    order = orders(:pending_order)

    get order_status_path(public_token: order.public_token)
    assert_response :success

    get orders_path(restaurant_id: @osteria)
    assert_response :success
    assert_no_match order.public_token, response.body
  end

  test "the honeypot path records nothing" do
    add_barolo_to_cart
    assert_no_difference "Order.count" do
      post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane", contact_reference: "http://spam.example" }
    end

    get orders_path(restaurant_id: @osteria)
    assert_response :success
  end

  test "a garbage order_tokens cookie does not break the index" do
    cookies[:order_tokens] = "not-json-and-not-signed"

    get orders_path(restaurant_id: @osteria)
    assert_response :success
  end

  test "the index does not 429 under repeated GETs, unlike create" do
    50.times do
      get orders_path(restaurant_id: @osteria)
      assert_response :success
    end
  end
end
