require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @osteria = restaurants(:osteria)
    @barolo = wines(:barolo)
    @customer = users(:customer)
  end

  def add_barolo_to_cart(quantity: 1)
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: quantity }
  end

  def last_order
    Order.order(:created_at).last
  end

  # --- create: guest ---

  test "a guest places an order end to end and lands on the status page" do
    add_barolo_to_cart

    post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }
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
    post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }

    get cart_path(restaurant_id: @osteria)
    assert_match I18n.t("cart.empty"), response.body
  end

  # --- create: signed-in ---

  test "a signed-in diner's order records the customer" do
    sign_in_as @customer
    add_barolo_to_cart

    post orders_path(restaurant_id: @osteria)

    assert_equal @customer, last_order.customer
  end

  # --- create: table ---

  test "ordering with a table records it" do
    table = restaurant_tables(:sala_t1)
    get table_menu_path(table_token: table.token)
    add_barolo_to_cart

    post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }

    assert_equal table, last_order.restaurant_table
  end

  test "ordering from /menu/:id records no table" do
    get menu_path(id: @osteria)
    add_barolo_to_cart

    post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }

    assert_nil last_order.restaurant_table
  end

  # --- strong params ---

  test "status, totals and ids cannot be mass-assigned through the form" do
    add_barolo_to_cart

    post orders_path(restaurant_id: @osteria), params: {
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
      post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane", contact_reference: "http://spam.example" }
    end
    # A real success redirects to the order's own status page — the
    # honeypot response is trivially distinguishable, not a fabricated
    # success (final review finding 4). It sets no flash of its own either.
    assert_redirected_to menu_path(id: @osteria)

    follow_redirect!
    assert_response :success
    assert_nil flash[:notice]
  end

  test "an array-valued honeypot still trips, closing the strong-params bypass" do
    add_barolo_to_cart

    assert_no_difference "Order.count" do
      post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane", contact_reference: [ "http://spam.example" ] }
    end
    assert_redirected_to menu_path(id: @osteria)
  end

  # --- rate limit ---

  test "the rate limit trips after 5 orders in a minute and the diner sees a flash" do
    add_barolo_to_cart

    5.times do
      post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }
      assert_response :redirect
      add_barolo_to_cart
    end

    post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }
    assert_redirected_to cart_path(restaurant_id: @osteria)

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
    # Stock now reserves one glass per order placed (Task 2). This loop
    # places IP_RATE_LIMIT orders of one glass each purely to exercise the
    # rate limiter, so the wine needs at least that many glasses on hand —
    # otherwise placement starts failing with :insufficient_stock partway
    # through, which is a different code path than the one under test here.
    @barolo.update!(available_glasses: OrdersController::IP_RATE_LIMIT)

    assert_difference "Order.count", OrdersController::IP_RATE_LIMIT do
      OrdersController::IP_RATE_LIMIT.times do
        reset!
        add_barolo_to_cart
        post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }
        assert_response :redirect
        assert_not_equal cart_url(restaurant_id: @osteria), response.location
      end
    end

    reset!
    add_barolo_to_cart
    assert_no_difference "Order.count" do
      post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }
    end
    assert_redirected_to cart_path(restaurant_id: @osteria)

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.rate_limited")), response.body
  end

  # --- empty cart ---

  test "an empty cart cannot be ordered" do
    post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }
    assert_redirected_to cart_path(restaurant_id: @osteria)

    follow_redirect!
    assert_match I18n.t("orders.errors.empty_cart"), response.body
  end

  # --- insufficient stock ---

  test "a cart quantity beyond available stock is refused and the diner sees a flash" do
    add_barolo_to_cart(quantity: @barolo.available_glasses + 1)

    assert_no_difference "Order.count" do
      post orders_path(restaurant_id: @osteria), params: { guest_name: "Jane" }
    end
    assert_redirected_to cart_path(restaurant_id: @osteria)

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
    post orders_path(restaurant_id: @osteria), params: { guest_name: "First Diner" }
    first_order = last_order

    reset!

    add_barolo_to_cart
    post orders_path(restaurant_id: @osteria), params: { guest_name: "Second Diner" }
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
      post orders_path(restaurant_id: @osteria), params: { guest_name: over_length_name }
    end
    assert_redirected_to cart_path(restaurant_id: @osteria)

    follow_redirect!
    assert_match ERB::Util.html_escape(I18n.t("orders.errors.order_invalid")), response.body
  end

  # --- inactive restaurant ---

  test "an inactive restaurant 404s on order creation" do
    inactive = restaurants(:inactive_restaurant)
    post orders_path(restaurant_id: inactive), params: { guest_name: "Jane" }
    assert_response :not_found
  end

  test "an order on an inactive restaurant 404s on the status page" do
    order = orders(:inactive_restaurant_order)
    get order_status_path(public_token: order.public_token)
    assert_response :not_found
  end
end
