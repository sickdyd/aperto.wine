require "test_helper"

# The controller/route wiring for the device-local order history.
#
# Not OrderHistoryTest: the runner loads every test file into one process and
# test/models/order_history_test.rb already holds that constant, which makes a
# second class of the same name a hard load error rather than a shadowed test.
class OrderHistoryFlowTest < ActionDispatch::IntegrationTest
  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
  end

  def add_barolo_to_cart(restaurant: @osteria, quantity: 1)
    post cart_items_path(restaurant_slug: restaurant.slug), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: quantity }
  end

  # Placement is refused without a table (:table_required), and only a
  # /t/:table_token visit puts one in the session (CustomerScoped#remember_table).
  # Scanning is how a real diner arrives anyway, so it belongs in the helper
  # rather than in each test.
  def table_for(restaurant)
    restaurant_tables(restaurant == @trattoria ? :trattoria_t1 : :sala_t1)
  end

  def place_order(restaurant: @osteria, guest_name: "Jane")
    get table_menu_path(table_token: table_for(restaurant).token)
    add_barolo_to_cart(restaurant: restaurant)
    post orders_path(restaurant_slug: restaurant.slug), params: { guest_name: guest_name }
    Order.order(:created_at).last
  end

  test "placing an order records it, and it appears on the device's index" do
    order = place_order

    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match order.public_token, response.body
  end

  test "two orders both appear on the index, newest first" do
    first = place_order(guest_name: "First Diner")
    second = place_order(guest_name: "Second Diner")

    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_operator response.body.index(second.public_token), :<, response.body.index(first.public_token)
  end

  test "a fresh device's index renders successfully and lists nothing" do
    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    # No order_tokens cookie was ever set, so none of this restaurant's
    # existing orders — fixtures or otherwise — should resolve for us.
    assert_no_match orders(:pending_order).public_token, response.body
    assert_no_match orders(:approved_order).public_token, response.body
  end

  test "an order placed at restaurant A does not appear on restaurant B's index" do
    order = place_order(restaurant: @osteria)

    get orders_path(restaurant_slug: @trattoria.slug)
    assert_response :success
    assert_no_match order.public_token, response.body
  end

  test "the index for an inactive restaurant 404s" do
    inactive = restaurants(:inactive_restaurant)
    get orders_path(restaurant_slug: inactive.slug)
    assert_response :not_found
  end

  test "GET /orders/:public_token does not add the order to the device's history" do
    order = orders(:pending_order)

    get order_status_path(public_token: order.public_token)
    assert_response :success

    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_no_match order.public_token, response.body
  end

  test "the honeypot path records nothing" do
    add_barolo_to_cart
    assert_no_difference "Order.count" do
      post orders_path(restaurant_slug: @osteria.slug), params: { guest_name: "Jane", contact_reference: "http://spam.example" }
    end

    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    # Not just a 200 — the index renders for any number of reasons. This is
    # the assertion that the history is genuinely still empty.
    assert_match I18n.t("orders.history.empty"), response.body
  end

  test "a garbage order_tokens cookie does not break the index" do
    cookies[:order_tokens] = "not-json-and-not-signed"

    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("orders.history.empty"), response.body
  end

  test "the index does not 429 under repeated GETs, unlike create" do
    50.times do
      get orders_path(restaurant_slug: @osteria.slug)
      assert_response :success
    end
  end

  # --- what the diner actually sees -------------------------------------
  #
  # This feature ships without system tests, so these assert on rendered
  # markup instead of driving a browser. They cover the guards and the copy;
  # what they cannot cover is a real browser (clicking, layout, and the
  # cookie genuinely outliving a process restart — the model test's expiry
  # assertion stands in for that last one).

  def history_link
    "href=\"#{orders_path(restaurant_slug: @osteria.slug)}\""
  end

  test "the menu shows no history link until this device has ordered here" do
    get published_menu_path(@osteria)
    assert_response :success
    assert_no_match history_link, response.body

    place_order

    get published_menu_path(@osteria)
    assert_response :success
    assert_match history_link, response.body
    assert_match I18n.t("orders.history.title"), response.body
  end

  test "a device that ordered at A sees no history link on B's menu" do
    place_order(restaurant: @osteria)

    get published_menu_path(@trattoria)
    assert_response :success
    assert_no_match "href=\"#{orders_path(restaurant_slug: @trattoria.slug)}\"", response.body
  end

  # The list would be a one-line copy of the page already open, so the status
  # page withholds the cross-link until a second order exists.
  test "the status page links to the list only once the device holds two orders" do
    first = place_order(guest_name: "First Diner")

    get order_status_path(public_token: first.public_token)
    assert_response :success
    assert_no_match history_link, response.body

    second = place_order(guest_name: "Second Diner")

    get order_status_path(public_token: second.public_token)
    assert_response :success
    assert_match history_link, response.body
    assert_match I18n.t("orders.history.other_orders"), response.body
  end

  test "each index row prints its status and total and links to its receipt" do
    order = place_order

    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match "href=\"#{order_status_path(public_token: order.public_token)}\"", response.body
    assert_match I18n.t("orders.status.statuses.#{order.status}"), response.body
    assert_match ApplicationController.helpers.format_cents(order.total_amount_cents), response.body
    # Expectation-setting: without this line the list reads as a permanent
    # account history rather than a day of one device's cookie.
    assert_match I18n.t("orders.history.retention"), response.body
  end

  test "a fresh device's index prints the empty state and the retention line" do
    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("orders.history.empty"), response.body
    assert_match I18n.t("orders.history.retention"), response.body
  end

  # The scenario the whole feature exists for: the session dies with the
  # browser, the signed order_tokens cookie does not, and the history is
  # rebuilt from that cookie alone. The session key is read from the app's
  # own config — hard-coding it would turn this into a test that deletes a
  # cookie which no longer exists and passes anyway.
  test "the history survives losing the session cookie" do
    order = place_order

    # A second glass in the cart, so the session has something live to lose.
    add_barolo_to_cart
    get published_menu_path(@osteria)
    assert_match "id=\"cart-bar\"", response.body

    cookies.delete(Rails.application.config.session_options[:key])

    get published_menu_path(@osteria)
    assert_response :success
    assert_no_match "id=\"cart-bar\"", response.body
    assert_match history_link, response.body

    get orders_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match order.public_token, response.body
  end
end
