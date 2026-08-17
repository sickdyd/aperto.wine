require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @osteria = restaurants(:osteria)
    @barolo = wines(:barolo)
    @customer = users(:customer)
    @table = restaurant_tables(:sala_t1)
    scan_table
  end

  # Placement is refused without a table (:table_required), and a
  # /t/:table_token visit is the only thing that puts one in the session (see
  # CustomerScoped#remember_table) — which is also how every real diner
  # arrives, by scanning the QR on the table they are sitting at. Every test
  # below therefore starts from a scanned table; reset! discards the cookie
  # jar, so anything that starts a fresh session scans again.
  def scan_table(table = @table)
    get table_menu_path(table_token: table.token)
  end

  def add_barolo_to_cart(quantity: 1)
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: quantity }
  end

  def last_order
    Order.order(:created_at).last
  end

  # --- create: guest ---

  test "a guest places an order end to end and lands on the status page" do
    add_barolo_to_cart

    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
    order = last_order
    assert_redirected_to order_status_path(public_token: order.public_token)

    follow_redirect!
    assert_response :success
    assert_match @barolo.name, response.body
    assert_nil order.customer
    assert_equal "Jane", order.guest_name
    assert_equal "pending", order.status
  end

  test "the cart is cleared after placing an order" do
    add_barolo_to_cart
    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match I18n.t("cart.empty"), response.body
  end

  # --- create: signed-in ---

  test "a signed-in diner's order records the customer" do
    sign_in_as @customer
    add_barolo_to_cart

    post orders_path(restaurant_slug: @osteria.slug)

    assert_equal @customer, last_order.customer
  end

  # --- create: table ---

  test "ordering with a table records it" do
    add_barolo_to_cart

    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }

    assert_equal @table, last_order.restaurant_table
  end

  # An order reserves its glasses the moment it is placed, so it has to belong
  # to somebody actually sitting in the restaurant. Without this, one visitor
  # who found the slug URL could reserve the whole cellar from anywhere and
  # only an owner cancelling each order would give it back.
  test "a diner who never scanned a table cannot place an order" do
    reset! # discard setup's scan: this diner arrived at the bare /menu/:id URL
    get published_menu_path(@osteria)
    add_barolo_to_cart
    available_before = @barolo.available_glasses

    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
    end
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    # Refusing must cost nothing: no reservation is taken and the cart is left
    # standing, so the same order goes through once the diner scans.
    assert_equal available_before, @barolo.reload.available_glasses

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.table_required")), response.body
  end

  # A retired token resolves to no table at all (CustomerScoped#current_table
  # re-validates on every read), so it must be refused exactly like never
  # having scanned — not quietly accepted as a tableless order.
  test "a retired table's token does not satisfy the table requirement" do
    reset!
    scan_table(restaurant_tables(:retired_table))
    add_barolo_to_cart

    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
    end

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.table_required")), response.body
  end

  # --- strong params ---

  test "status, totals and ids cannot be mass-assigned through the form" do
    add_barolo_to_cart

    post orders_path(restaurant_slug: @osteria.slug), params: {
      guest_name: "Jane", status: "approved", total_amount_cents: 999_999,
      customer_id: @customer.id, public_token: "hijacked-token"
    }

    order = last_order
    assert_equal "pending", order.status
    assert_not_equal 999_999, order.total_amount_cents
    assert_nil order.customer
    assert_not_equal "hijacked-token", order.public_token
  end

  # --- honeypot ---

  test "the honeypot creates no order and redirects to the menu, distinguishable from a real success" do
    add_barolo_to_cart
    follow_redirect! # render the menu so the add's own flash doesn't leak into the assertion below

    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane", contact_reference: "http://spam.example" }
    end
    # A real success redirects to the order's own status page — the
    # honeypot response is trivially distinguishable, not a fabricated
    # success (final review finding 4). It sets no flash of its own either.
    assert_redirected_to published_menu_path(@osteria)

    follow_redirect!
    assert_response :success
    assert_nil flash[:notice]
  end

  test "an array-valued honeypot still trips, closing the strong-params bypass" do
    add_barolo_to_cart

    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane", contact_reference: [ "http://spam.example" ] }
    end
    assert_redirected_to published_menu_path(@osteria)
  end

  # --- rate limit ---

  test "the rate limit trips after 5 orders in a minute and the diner sees a flash" do
    add_barolo_to_cart

    5.times do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
      assert_response :redirect
      add_barolo_to_cart
    end

    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.rate_limited")), response.body
  end

  # The reviewer's exploit: a fresh cookie jar per request gives every
  # request a brand-new session.id, so the session-scoped limiter above
  # never trips — session.id is always present by the time #create runs
  # (Cart is session-backed), so its IP fallback never engages either. This
  # proves the IP-scoped limiter closes that bypass: IP_RATE_LIMIT distinct
  # sessions from the same remote_ip (127.0.0.1 for every integration test
  # request) all succeed, and the next one — still a brand-new session —
  # is the one that trips.
  test "the IP rate limit trips across distinct sessions, closing the session-only bypass" do
    # Stock now reserves one glass per order placed (Task 2). This loop places
    # IP_RATE_LIMIT orders, then one more beyond that to trip the limiter, so
    # the wine has to outlast all of them: if it ran dry the final request
    # would fail on :wine_unavailable before ever reaching the limiter, and
    # assert_no_difference "Order.count" would pass for the wrong reason.
    #
    # Doubled rather than IP_RATE_LIMIT+1, which is the exact headroom for
    # add_barolo_to_cart's current default of one glass per order and nothing
    # more — raising that default would empty the wine and the failure would
    # read as a broken rate limiter rather than a thin fixture.
    @barolo.update!(available_glasses: OrdersController::IP_RATE_LIMIT * 2)

    assert_difference "Order.count", OrdersController::IP_RATE_LIMIT do
      OrdersController::IP_RATE_LIMIT.times do
        reset!
        scan_table
        add_barolo_to_cart
        post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
        assert_response :redirect
        assert_not_equal cart_url(restaurant_slug: @osteria.slug), response.location
      end
    end

    reset!
    scan_table
    add_barolo_to_cart
    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
    end
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.rate_limited")), response.body
  end

  # --- empty cart ---

  test "an empty cart cannot be ordered" do
    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    follow_redirect!
    assert_match I18n.t("orders.errors.empty_cart"), response.body
  end

  # --- insufficient stock ---

  test "a cart quantity beyond available stock is refused and the diner sees a flash" do
    add_barolo_to_cart(quantity: 5)
    # Cart#add itself now refuses a quantity beyond stock (Cart's convenience
    # guard), so the only way to reach this flash is a line that was fine
    # when added and fell short of stock only afterward.
    @barolo.update!(available_glasses: 4)

    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }
    end
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    follow_redirect!
    assert_match I18n.t("orders.errors.insufficient_stock"), response.body
  end

  # --- show ---

  test "the status page renders for a valid token" do
    order = orders(:pending_order)
    get order_status_path(public_token: order.public_token)
    assert_response :success
  end

  test "an unknown token 404s" do
    get order_status_path(public_token: "totally-unknown-token-zzz")
    assert_response :not_found
  end

  # Both orders are placed in genuinely separate sessions — reset! discards
  # the cookie jar, so nothing about "who's browsing" carries over between
  # the two placements. This is what actually rules out any lookup that
  # (accidentally or otherwise) leans on session/current-user state instead
  # of the public_token alone.
  test "one diner cannot read another's order" do
    add_barolo_to_cart
    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "First Diner" }
    first_order = last_order

    reset!
    scan_table

    add_barolo_to_cart
    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Second Diner" }
    second_order = last_order

    get order_status_path(public_token: second_order.public_token)
    assert_response :success
    assert_match "Second Diner", response.body
    assert_no_match "First Diner", response.body

    get order_status_path(public_token: first_order.public_token)
    assert_response :success
    assert_match "First Diner", response.body
    assert_no_match "Second Diner", response.body
  end

  # --- order_invalid ---

  test "an over-length guest name fails cleanly with a flash and no row, not a 500" do
    add_barolo_to_cart
    over_length_name = "a" * 65

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: over_length_name }
    end
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.order_invalid")), response.body
  end

  # --- inactive restaurant ---

  test "an inactive restaurant 404s on order creation" do
    inactive = restaurants(:inactive_restaurant)
    post orders_path(restaurant_slug: inactive.slug), params: { guest_name: "Jane" }
    assert_response :not_found
  end

  test "an order on an inactive restaurant 404s on the status page" do
    order = orders(:inactive_restaurant_order)
    get order_status_path(public_token: order.public_token)
    assert_response :not_found
  end

  # --- geofencing ---
  #
  # The geofence ships off, so osteria's fixture leaves it disabled and the
  # tests that want it on turn it on themselves — flipping the fixture would
  # change behaviour across the whole suite.

  # Derived from a real distance measurement rather than a hardcoded latitude,
  # for the reason spelled out in GeofenceTest#point_at.
  def point_at(restaurant, meters)
    origin = [ restaurant.latitude.to_f, restaurant.longitude.to_f ]
    probe = 0.001
    meters_per_degree = (Geocoder::Calculations.distance_between(origin, [ origin.first + probe, origin.last ], units: :km) * 1000) / probe
    [ origin.first + (meters / meters_per_degree), origin.last ]
  end

  test "an in-range fix against a geofenced restaurant places the order and lands on the status page" do
    @osteria.update!(geofence_enabled: true)
    add_barolo_to_cart
    point = point_at(@osteria, 5)

    post orders_path(restaurant_slug: @osteria.slug), params: {
      guest_name: "Jane", latitude: point.first, longitude: point.last, accuracy: 12
    }

    order = last_order
    assert_redirected_to order_status_path(public_token: order.public_token)
    assert order.location_status_verified?
    assert_equal 5, order.distance_meters
    assert_equal 12, order.location_accuracy_meters
  end

  test "an out-of-range fix creates no order and redirects back to the cart with a flash" do
    @osteria.update!(geofence_enabled: true)
    add_barolo_to_cart
    point = point_at(@osteria, 4000)

    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: {
        guest_name: "Jane", latitude: point.first, longitude: point.last, accuracy: 12
      }
    end
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    # No number of any kind reaches the diner. A message naming the measured
    # distance would be a range oracle: a sender could move a claimed position
    # around and bisect the replies to recover the restaurant's stored
    # coordinates and radius.
    assert_no_match(/\d/, flash[:alert])

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.location_out_of_range")), response.body
  end

  test "a geofenced restaurant still accepts an order with no location params at all" do
    @osteria.update!(geofence_enabled: true)
    add_barolo_to_cart

    post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }

    order = last_order
    assert_redirected_to order_status_path(public_token: order.public_token)
    assert order.location_status_unverified?
  end

  test "a restaurant with the geofence off is unaffected by a location it is sent" do
    add_barolo_to_cart
    point = point_at(@osteria, 4000)

    post orders_path(restaurant_slug: @osteria.slug), params: {
      guest_name: "Jane", latitude: point.first, longitude: point.last, accuracy: 12
    }

    order = last_order
    assert_redirected_to order_status_path(public_token: order.public_token)
    assert order.location_status_not_checked?
    assert_nil order.distance_meters
  end

  test "garbage location params never raise and are treated as no fix" do
    # Two shapes at once: a non-numeric scalar, which Geofence rejects, and a
    # non-scalar, which Strong Parameters drops to nil before Geofence ever
    # sees it. Both must land on "no usable fix", not a 500.
    @osteria.update!(geofence_enabled: true)

    [ { latitude: "abc", longitude: "def", accuracy: "ghi" },
      { latitude: [ 1 ], longitude: { a: 2 }, accuracy: [ 3 ] } ].each do |junk|
      add_barolo_to_cart

      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane" }.merge(junk)

      order = last_order
      assert_redirected_to order_status_path(public_token: order.public_token)
      assert order.location_status_unverified?, junk.inspect
    end
  end
end
