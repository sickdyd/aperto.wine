require "test_helper"

class PlaceOrderTest < ActiveSupport::TestCase
  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
    @gavi = wines(:gavi)
    @franciacorta = wines(:trattoria_franciacorta)
    @customer = users(:customer)
    # Placement now refuses without a table (:table_required), so every call
    # below hands one over. The table is the ordinary case, not the special
    # one — a diner reaches the menu by scanning the QR on their table.
    @table = restaurant_tables(:sala_t1)
    @trattoria_table = restaurant_tables(:trattoria_t1)
  end

  def cart_for(restaurant, session: {})
    Cart.new(session: session, restaurant: restaurant)
  end

  test "places a guest order and snapshots the current price" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    original_price = @barolo.price_for_glass(125)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

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
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    original_price = @barolo.price_for_glass(125)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")
    order = result.order

    # Reserving the glasses bumped the wine's lock_version (decrement! goes
    # through update_counters, which maintains the locking column), so this
    # setup object is now stale by design — the reload is the owner-form
    # workflow in miniature, not a workaround.
    @barolo.reload.update!(price_125ml_cents: original_price + 5000)

    assert_equal original_price, order.order_items.first.reload.unit_price_cents
  end

  test "a mixed bottle and glass cart produces order items with the right serving and snapshotted prices" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 1)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    original_bottle_price = @barolo.price_bottle_cents
    original_glass_price = @barolo.price_for_glass(125)

    # A table, because placement reserves stock and is refused without one
    # (:table_required) — see the guard test below.
    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    order = result.order
    assert_equal 2, order.order_items.count

    bottle_item = order.order_items.find(&:bottle?)
    assert_equal @barolo, bottle_item.wine
    assert_nil bottle_item.glass_size_ml
    assert_equal 1, bottle_item.quantity
    assert_equal original_bottle_price, bottle_item.unit_price_cents

    glass_item = order.order_items.find(&:glass?)
    assert_equal @barolo, glass_item.wine
    assert_equal 125, glass_item.glass_size_ml
    assert_equal 2, glass_item.quantity
    assert_equal original_glass_price, glass_item.unit_price_cents
  end

  test "a bottle that lost its price after being added aborts the whole placement" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 1)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @barolo.update!(price_bottle_cents: 0)

    # A table, so the answer is about the cart. The table guard runs ahead of
    # the cart guards (see PlaceOrder), so without one this would report
    # :table_required and never exercise the dropped-bottle path at all.
    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: nil)

      assert_not result.success?
      assert_equal :items_unavailable, result.error
      assert_equal 1, result.dropped_items.size
      assert_equal @barolo.id, result.dropped_items.first.wine_id
      assert_equal "bottle", result.dropped_items.first.serving
    end
  end

  test "an empty cart is refused" do
    cart = cart_for(@osteria)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: nil)

    assert_not result.success?
    assert_equal :empty_cart, result.error
    assert_nil result.order
  end

  test "a wine that went unavailable after being added aborts the whole order and reports it" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: nil)

      assert_not result.success?
      assert_equal :items_unavailable, result.error
    end
  end

  # --- final review finding 1: the diner must be told which items are offending ---

  test "an aborted order reports which items dropped, not just a bare symbol" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: nil)

    assert_not result.success?
    assert_equal 1, result.dropped_items.size
    assert_equal @gavi.id, result.dropped_items.first.wine_id
    assert_equal :wine_unavailable, result.dropped_items.first.reason
  end

  test "a successful order reports no dropped items" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_empty result.dropped_items
  end

  test "only the ordering restaurant's cart is cleared" do
    session = {}
    osteria_cart = cart_for(@osteria, session: session)
    trattoria_cart = cart_for(@trattoria, session: session)
    osteria_cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    trattoria_cart.add(wine_id: @franciacorta.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: osteria_cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_empty osteria_cart.items
    assert_equal [ @franciacorta ], trattoria_cart.items.map(&:wine)
  end

  test "a signed-in customer's order records the customer and no guest name" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: @customer, guest_name: nil)

    assert result.success?
    assert_equal @customer, result.order.customer
    assert_nil result.order.guest_name
  end

  test "the table is attached when present" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal @table, result.order.restaurant_table
  end

  # Placement reserves stock, and this surface is unauthenticated and
  # reachable from a bare slug URL — without this guard one visitor who never
  # entered the restaurant could reserve the whole cellar, and only an owner
  # cancelling each order would give it back.
  test "a placement with no table is refused and creates nothing" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    available_before = @barolo.available_glasses

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: nil, customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :table_required, result.error
      assert_nil result.order
    end

    # Nothing reserved and nothing cleared: the diner scans their table's QR
    # and sends the same cart.
    assert_equal available_before, @barolo.reload.available_glasses
    assert_equal [ @barolo ], cart.items.map(&:wine)
  end

  # The table guard runs ahead of the cart guards on purpose (see PlaceOrder),
  # so a diner with no table hears about the table rather than about a cart
  # they cannot order from at any size.
  test "the table guard is answered before an empty cart is" do
    result = PlaceOrder.call(cart: cart_for(@osteria), restaurant: @osteria, table: nil, customer: nil, guest_name: nil)

    assert_equal :table_required, result.error
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
    invalid_item = CartItem.new(wine: @barolo, serving: "glass", glass_size_ml: 125, quantity: 0)
    fake_cart = Struct.new(:items, :dropped_items).new([ invalid_item ], [])

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: fake_cart, restaurant: @osteria, table: @table, customer: nil, guest_name: nil)

      assert_not result.success?
      assert_equal :order_invalid, result.error
    end
  end

  test "stock is decremented by the line quantity at placement" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    available_before = @barolo.available_glasses

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal available_before - 2, @barolo.reload.available_glasses
  end

  # Order#cancel! releases only what an order says it holds, so an order that
  # took the decrement and did not say so would have its glasses stranded.
  test "an order that reserved stock is flagged as holding it" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert result.order.stock_reserved?
  end

  test "a line short of stock aborts the whole placement and reserves nothing" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 5)
    # Cart#add itself now refuses a quantity beyond stock (Cart's convenience
    # guard), so the only way to reach PlaceOrder's own lock-checked guard is
    # a line that was fine when added and fell short only afterward.
    @barolo.update!(available_glasses: 4)

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :insufficient_stock, result.error
      assert_nil result.order
    end
    assert_equal 4, @barolo.reload.available_glasses
  end

  # The lock check must run against the running total for a wine, not each
  # cart line in isolation — two lines for the same wine at different glass
  # sizes both draw from the same available_glasses pool, so a naive
  # per-line comparison against the pre-loop snapshot would let this through.
  test "two lines for the same wine at different glass sizes are checked against their combined quantity" do
    cart = cart_for(@osteria)
    # Cart#add itself now aggregates a wine's stock across glass sizes (its
    # own convenience guard — see Cart#over_stock_wine_ids), so building
    # this cart needs generous stock at add-time. The assertion under test
    # is that PlaceOrder's own lock-checked guard catches the combined
    # total once stock falls back before checkout, independent of Cart's
    # guard.
    @barolo.update!(available_glasses: 12)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 100, quantity: 6)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 6)
    @barolo.update!(available_glasses: 10)

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :insufficient_stock, result.error
    end
    assert_equal 10, @barolo.reload.available_glasses
  end

  # --- bottles reserve nothing ---
  #
  # There is no bottle stock column: a positive price_bottle_cents is the
  # whole of what "bottle available" means (Wine#bottle_available?), and a
  # wine is deliberately still bottle-orderable with zero glasses left. So a
  # bottle line takes no decrement and is never refused for want of glasses.

  test "a bottle line decrements no glasses" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 3)
    available_before = @barolo.available_glasses

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal available_before, @barolo.reload.available_glasses
  end

  test "a bottle line is placed even when the wine has no glasses left at all" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 2)
    @barolo.update!(available_glasses: 0)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal 0, @barolo.reload.available_glasses
    assert_equal 2, result.order.order_items.sole.quantity
  end

  # A mixed cart's glass line spends exactly its own quantity — the bottle
  # line sitting beside it neither adds to the draw nor shields it.
  test "in a mixed cart only the glass line's quantity is reserved" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 4)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    available_before = @barolo.available_glasses

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert_equal available_before - 2, @barolo.reload.available_glasses
  end

  # stock_reserved marks "placed by the placement-era code path", not "took a
  # decrement" — a bottle-only order takes none and is still flagged, which is
  # what keeps it distinguishable from a pre-deploy legacy order (whose false
  # flag is the only thing stopping cancel! inventing glasses). Pinned because
  # it looks like a redundant write and is not.
  test "a bottle-only order is still stamped as placement-era stock_reserved" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    assert result.order.stock_reserved?
  end

  # The two halves of the invariant are pinned separately elsewhere; this is
  # the only test that closes the loop on real PlaceOrder output. What
  # reserve_stock! spends and what cancel! releases must agree exactly, or a
  # mixed same-wine order leaks or invents glasses every round trip.
  test "placing then cancelling a mixed same-wine order returns stock to exactly where it started" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 3)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    available_before = @barolo.available_glasses

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    # Only the two glass lines were spent; the three bottles cost nothing.
    assert_equal available_before - 3, @barolo.reload.available_glasses

    assert result.order.cancel!
    assert_equal available_before, @barolo.reload.available_glasses
  end

  # The existence guard is about the row having vanished under the read, not
  # about stock, so it still covers a bottle-only cart — without it this race
  # comes back as an FK violation from order_items.create!, i.e. a 500.
  test "a wine deleted under a bottle-only cart fails cleanly, not with a 500" do
    # The fixture prices franciacorta by the glass only, and a bottle price
    # is exactly what makes a wine bottle-orderable (Wine#bottle_available?).
    # franciacorta is used here for the same reason as the glass-side test
    # below: no order_items fixture references it, so the FK lets it delete.
    @franciacorta.update!(price_bottle_cents: 6000)
    cart = cart_for(@trattoria)
    cart.add(wine_id: @franciacorta.id, serving: "bottle", quantity: 1)
    cart.items

    @franciacorta.destroy!

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @trattoria, table: @trattoria_table,
                               customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :items_unavailable, result.error
    end
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
    cart.add(wine_id: @franciacorta.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.items

    @franciacorta.destroy!

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = PlaceOrder.call(cart: cart, restaurant: @trattoria, table: @trattoria_table, customer: nil, guest_name: "Jane")

      assert_not result.success?
      assert_equal :items_unavailable, result.error
      assert_nil result.order
    end
  end

  test "calculate_total! is applied so the order total reflects its items" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    expected_total = @barolo.price_for_glass(125) * 2

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert_equal expected_total, result.order.total_amount_cents
  end

  # --- geofencing ---
  #
  # Geofence itself is exercised exhaustively in test/services/geofence_test.rb.
  # What is proved here is only the wiring: that each verdict reaches the order
  # row (or blocks it) intact.

  # A point due north of the restaurant, `meters` away. Same derivation as
  # GeofenceTest#point_at, and for the same reason: these tests are only
  # meaningful if they track the fixture's radius and Geofence's accuracy cap,
  # and a hardcoded latitude would quietly stop doing that the first time
  # either moves.
  def point_at(restaurant, meters)
    origin = [ restaurant.latitude.to_f, restaurant.longitude.to_f ]
    probe = 0.001
    meters_per_degree = meters_between(origin, [ origin.first + probe, origin.last ]) / probe
    [ origin.first + (meters / meters_per_degree), origin.last ]
  end

  def meters_between(from, to)
    Geocoder::Calculations.distance_between(from, to, units: :km) * 1000
  end

  def place_at(cart, restaurant, point, accuracy:)
    PlaceOrder.call(
      cart: cart, restaurant: restaurant, table: @table, customer: nil, guest_name: "Jane",
      latitude: point.first, longitude: point.last, accuracy: accuracy
    )
  end

  test "a disabled geofence records no location claim even when a good fix is supplied" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = place_at(cart, @osteria, point_at(@osteria, 5), accuracy: 12)

    assert result.success?
    order = result.order
    assert order.location_status_not_checked?
    assert_nil order.distance_meters
    assert_nil order.location_accuracy_meters
  end

  test "an in-range fix is stamped onto the order" do
    @osteria.update!(geofence_enabled: true)
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = place_at(cart, @osteria, point_at(@osteria, 5), accuracy: 12)

    assert result.success?
    order = result.order
    assert order.location_status_verified?
    assert_equal 5, order.distance_meters
    assert_equal 12, order.location_accuracy_meters
  end

  test "a diner who supplies no fix still places the order, unverified" do
    # The product decision, not an oversight: a denied browser prompt (or a
    # device that simply cannot get a fix) must not cost a real order.
    @osteria.update!(geofence_enabled: true)
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = PlaceOrder.call(cart: cart, restaurant: @osteria, table: @table, customer: nil, guest_name: "Jane")

    assert result.success?
    order = result.order
    assert order.location_status_unverified?
    assert_nil order.distance_meters
    assert_nil order.location_accuracy_meters
  end

  test "a fix too imprecise to judge places the order and records the accuracy but no distance" do
    @osteria.update!(geofence_enabled: true)
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    too_wide = Geofence::MAX_ACCURACY_METERS + 1

    result = place_at(cart, @osteria, point_at(@osteria, 5), accuracy: too_wide)

    assert result.success?
    order = result.order
    assert order.location_status_unverified?
    assert_equal too_wide, order.location_accuracy_meters
    assert_nil order.distance_meters
  end

  test "an out-of-range fix places no order and leaves the cart intact" do
    # The cart surviving is the point: a diner who walks closer must be able to
    # retry the order they already built rather than rebuild it from scratch.
    @osteria.update!(geofence_enabled: true)
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = place_at(cart, @osteria, point_at(@osteria, 4000), accuracy: 12)

      assert_not result.success?
      assert_equal :location_out_of_range, result.error
      assert_nil result.order
    end

    assert_equal [ @barolo ], cart.items.map(&:wine)
    assert_equal 2, cart.items.first.quantity
  end
end
