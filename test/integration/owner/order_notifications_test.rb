require "test_helper"

# The endpoint the owner's dashboard polls for orders that have arrived since
# it last looked. It is the only place the "live" part of the live wine list is
# actually decided, so the cases that matter are the ones about what it refuses
# to say: nothing at all when nothing has changed, nothing about a restaurant
# that is not this owner's, and nothing twice.
module Owner
  class OrderNotificationsTest < ActionDispatch::IntegrationTest
    WINDOW_HEADER = "X-Order-Window".freeze

    setup do
      @owner = users(:owner)
      # No order fixtures hang off enoteca, so every case here starts from a
      # window this test wrote itself.
      @restaurant = restaurants(:enoteca)
    end

    def place_order(status: :pending, created_at: Time.current)
      Order.create!(
        restaurant: @restaurant, status: status,
        total_amount_cents: 1800, created_at: created_at
      )
    end

    def poll(known: [], count: nil)
      get notifications_owner_restaurant_orders_path(restaurant_id: @restaurant),
          params: { known: Array(known).map(&:to_s), count: count }.compact,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    def window_ids
      response.headers[WINDOW_HEADER].to_s.split(",").map(&:to_i)
    end

    # --- Authorization ---

    test "requires authentication" do
      poll
      assert_redirected_to sign_in_path
    end

    test "a customer is turned away" do
      sign_in_as users(:customer)
      poll
      assert_redirected_to root_path
    end

    test "an owner cannot poll another owner's restaurant" do
      sign_in_as @owner
      @restaurant = restaurants(:trattoria)

      poll
      assert_response :not_found
    end

    # --- Nothing to report ---

    test "answers no content when the window and the tally are both unchanged" do
      order = place_order
      sign_in_as @owner

      poll(known: [ order.id ], count: 1)

      assert_response :no_content
      assert_equal [ order.id ], window_ids
    end

    test "a restaurant with no orders at all reports an empty window" do
      sign_in_as @owner

      poll(count: 0)

      assert_response :no_content
      assert_empty window_ids
    end

    # --- New orders ---

    test "announces an order the client has not seen" do
      order = place_order
      sign_in_as @owner

      poll(count: 0)

      assert_response :success
      assert_match "turbo-stream", response.media_type
      assert_match "##{order.id}", response.body
      assert_equal [ order.id ], window_ids
    end

    test "does not announce the same order twice" do
      order = place_order
      sign_in_as @owner

      poll(known: [ order.id ], count: 1)
      assert_response :no_content

      newer = place_order
      poll(known: window_ids, count: 1)

      assert_response :success
      assert_match "##{newer.id}", response.body
      assert_no_match(/##{order.id}\b/, response.body)
    end

    test "announces at most a window's worth of orders in one answer" do
      placed = (Order::NOTIFICATION_WINDOW + 3).times.map { |i| place_order(created_at: i.seconds.ago) }
      sign_in_as @owner

      poll(count: 0)

      assert_response :success
      assert_equal Order::NOTIFICATION_WINDOW, window_ids.size
      oldest = placed.min_by(&:created_at)
      assert_no_match(/##{oldest.id}\b/, response.body)
    end

    # --- The badge ---

    test "restates the pending tally when it has moved" do
      place_order
      place_order(status: :approved)
      sign_in_as @owner

      poll(count: 0)

      assert_response :success
      assert_select "turbo-stream[action=?][target=?]", "replace", "owner-orders-badge"
      assert_match "1", response.body
    end

    test "restates the tally even when no order is new" do
      order = place_order
      sign_in_as @owner

      poll(known: [ order.id ], count: 7)

      assert_response :success
      assert_select "turbo-stream[action=?][target=?]", "replace", "owner-orders-badge"
    end

    # --- Untrusted input ---

    test "a junk cursor announces nothing rather than everything" do
      order = place_order
      sign_in_as @owner

      poll(known: [ "not-an-id", order.id.to_s ], count: 1)

      assert_response :no_content
    end

    test "a cursor that is not a list is ignored rather than raising" do
      place_order
      sign_in_as @owner

      get notifications_owner_restaurant_orders_path(restaurant_id: @restaurant),
          params: { known: { evil: "1" }, count: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
    end

    test "an oversized cursor list cannot be used to grow the query" do
      order = place_order
      sign_in_as @owner

      poll(known: Array.new(500) { |i| i } + [ order.id ], count: 1)

      # Only the first window's worth is read, so the real id at the tail is
      # never seen and the order is announced.
      assert_response :success
      assert_match "##{order.id}", response.body
    end

    # --- Only this restaurant ---

    test "another restaurant's orders never enter the window" do
      mine = place_order
      Order.create!(restaurant: restaurants(:osteria), status: :pending, total_amount_cents: 100)
      sign_in_as @owner

      poll(count: 0)

      assert_equal [ mine.id ], window_ids
    end
  end
end
