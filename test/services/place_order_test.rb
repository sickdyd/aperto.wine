require "test_helper"

class PlaceOrderTest < ActiveSupport::TestCase
  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
    @gavi = wines(:gavi)
    @franciacorta = wines(:trattoria_franciacorta)
    @customer = users(:customer)
    @table = restaurant_tables(:sala_t1)
  end

  def cart_for(restaurant, session: {})
    Cart.new(session: session, restaurant: restaurant)
  end

  test "places a guest order and snapshots the current price" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    original_price = @barolo.price_for_glass(125)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert result.success?
    order = result.order
    assert_nil order.customer
    assert_equal "Jane", order.guest_name
    assert_equal "pending", order.status
    assert_equal 1, order.order_items.count
    item = order.order_items.first
    assert_equal @barolo, item.wine
    assert_equal 125, item.glass_size_ml
    assert_equal 2, item.quantity
    assert_equal original_price, item.unit_price_cents
  end

  test "a later price change never rewrites the placed order" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    original_price = @barolo.price_for_glass(125)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")
    order = result.order

    @barolo.update!(price_125ml_cents: original_price + 5000)

    assert_equal original_price, order.order_items.first.reload.unit_price_cents
  end

  test "an empty cart is refused" do
    cart = cart_for(@osteria)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: nil)

    assert_not result.success?
    assert_equal :empty_cart, result.error
    assert_nil result.order
  end

  test "a wine that went unavailable after being added aborts the whole order and reports it" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: nil)

      assert_not result.success?
      assert_equal :items_unavailable, result.error
    end
  end

  # --- final review finding 1: the diner must be told which items are offending ---

  test "an aborted order reports which items dropped, not just a bare symbol" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: nil)

    assert_not result.success?
    assert_equal 1, result.dropped_items.size
    assert_equal @gavi.id, result.dropped_items.first.wine_id
    assert_equal :wine_unavailable, result.dropped_items.first.reason
  end

  test "a successful order reports no dropped items" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_empty result.dropped_items
  end

  test "only the ordering restaurant's cart is cleared" do
    session = {}
    osteria_cart = cart_for(@osteria, session: session)
    trattoria_cart = cart_for(@trattoria, session: session)
    osteria_cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    trattoria_cart.add(wine_id: @franciacorta.id, glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: osteria_cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_empty osteria_cart.items
    assert_equal [ @franciacorta ], trattoria_cart.items.map(&:wine)
  end

  test "a signed-in customer's order records the customer and no guest name" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: @customer, guest_name: nil)

    assert result.success?
    assert_equal @customer, result.order.customer
    assert_nil result.order.guest_name
  end

  test "the table is attached when present" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal @table, result.order.restaurant_table
  end

  test "the table is nil when absent" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_nil result.order.restaurant_table
  end

  test "nothing is created when the transaction fails" do
    # Cart itself now refuses a zero (or nil) price before it ever reaches
    # PlaceOrder (final review finding 2), so the only way left to reach
    # OrderItem's own validation is a fake cart exposing an already-invalid
    # CartItem — quantity 0, which Cart's own clamping never produces but
    # OrderItem's numericality validation rejects. This exercises the
    # defensive :order_invalid branch documented on Result: proof the
    # transaction rolls back cleanly rather than leaving a partial order
    # behind.
    invalid_item = CartItem.new(wine: @barolo, glass_size_ml: 125, quantity: 0)
    fake_cart = Struct.new(:items, :dropped_items).new([ invalid_item ], [])

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: fake_cart, restaurant: @osteria, table: nil, customer: nil, guest_name: nil)

      assert_not result.success?
      assert_equal :order_invalid, result.error
    end
  end

  test "stock is not decremented at placement" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    available_before = @barolo.available_glasses

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal available_before, @barolo.reload.available_glasses
  end

  test "calculate_total! is applied so the order total reflects its items" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    expected_total = @barolo.price_for_glass(125) * 2

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert_equal expected_total, result.order.total_amount_cents
  end
end
