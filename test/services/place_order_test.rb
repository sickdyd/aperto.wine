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

  test "stock is decremented by the line quantity at placement" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    available_before = @barolo.available_glasses

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal available_before - 2, @barolo.reload.available_glasses
  end

  test "a line short of stock aborts the whole placement and reserves nothing" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: @barolo.available_glasses + 1)

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :insufficient_stock, result.error
      assert_nil result.order
    end
    assert_equal 10, @barolo.reload.available_glasses
  end

  # The lock check must run against the running total for a wine, not each
  # cart line in isolation — two lines for the same wine at different glass
  # sizes both draw from the same available_glasses pool, so a naive
  # per-line comparison against the pre-loop snapshot would let this through.
  test "two lines for the same wine at different glass sizes are checked against their combined quantity" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 100, quantity: 6)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 6)

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :insufficient_stock, result.error
    end
    assert_equal 10, @barolo.reload.available_glasses
  end

  # Cart#items is read once at the top of #call and memoized; the locked
  # re-check happens later, in its own query, inside build_order!'s
  # transaction. That gap is a real window: the wine can be deleted after
  # Cart#items already resolved it but before the lock query runs. Force
  # that ordering by loading cart.items first (so the CartItem's wine
  # reference is already resolved from the pre-deletion state), then delete
  # the row, then place. #franciacorta is used here specifically because,
  # unlike @barolo/@gavi, no order_items fixture references it, so the FK
  # constraint doesn't block the delete.
  test "a wine deleted between the cart's read and the locked re-check fails cleanly, not with a 500" do
    cart = cart_for(@trattoria)
    cart.add(wine_id: @franciacorta.id, glass_size_ml: 125, quantity: 1)
    cart.items

    @franciacorta.destroy!

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @trattoria, table: nil, customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :items_unavailable, result.error
      assert_nil result.order
    end
  end

  test "calculate_total! is applied so the order total reflects its items" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    expected_total = @barolo.price_for_glass(125) * 2

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

    assert_equal expected_total, result.order.total_amount_cents
  end
end
