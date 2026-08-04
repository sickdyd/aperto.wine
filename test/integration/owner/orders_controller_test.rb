require "test_helper"

module Owner
  class OrdersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
      @pending_order = orders(:pending_order)
      @approved_order = orders(:approved_order)
    end

    # --- Authorization ---

    test "GET /owner/restaurants/:id/orders requires authentication" do
      get owner_restaurant_orders_path(restaurant_id: @restaurant)
      assert_redirected_to sign_in_path
    end

    test "GET /owner/restaurants/:id/orders as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_restaurant_orders_path(restaurant_id: @restaurant)
      assert_redirected_to root_path
    end

    # --- INDEX ---

    test "GET /owner/restaurants/:id/orders as owner renders index" do
      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant)
      assert_response :success
    end

    test "GET /owner/restaurants/:id/orders filtered by status" do
      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant), params: { status: "pending" }
      assert_response :success
    end

    test "GET /owner/restaurants/:id/orders renders successfully for a guest order and shows the guest's name" do
      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant)
      assert_response :success
      assert_match "Jane Diner", response.body
    end

    test "GET /owner/restaurants/:id/orders renders the board as a ledger table with tabular figures" do
      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant)

      assert_select "table.ledger-table"
      assert_select "table.ledger-table td.cell-num", text: /€/, count: 3
      # Table, order, items, qty, total, placed, status, actions.
      assert_select "table.ledger-table thead th", count: 8
    end

    test "GET /owner/restaurants/:id/orders states each status in words, not colour alone" do
      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant)

      %w[pending approved].each do |status|
        assert_select ".badge", text: /#{Regexp.escape(I18n.t("owner.orders.statuses.#{status}"))}/
      end
    end

    test "GET /owner/restaurants/:id/orders shows the table for an order placed at one" do
      table = restaurant_tables(:sala_t1)
      @pending_order.update!(restaurant_table: table)

      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant)

      assert_match table.name, response.body
      assert_match table.area, response.body
    end

    test "GET /owner/restaurants/:id/orders with a status that matches nothing renders the filtered empty state" do
      @restaurant.orders.update_all(status: Order.statuses[:approved])

      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant), params: { status: "cancelled" }

      assert_response :success
      assert_select ".empty-state", text: /#{Regexp.escape(I18n.t("owner.orders.empty_filtered_title"))}/
    end

    test "GET /owner/restaurants/:id/orders with no orders at all reassures rather than alarms" do
      @restaurant.orders.destroy_all

      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant)

      assert_select ".empty-state", text: /#{Regexp.escape(I18n.t("owner.orders.empty_title"))}/
      assert_select ".empty-state", text: /#{Regexp.escape(I18n.t("owner.orders.empty_description"))}/
    end

    test "GET /owner/restaurants/:id/orders links each row through to its docket" do
      sign_in_as @owner
      get owner_restaurant_orders_path(restaurant_id: @restaurant)

      assert_select "a[href=?]", owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
    end

    # --- SHOW ---

    test "GET /owner/restaurants/:id/orders/:id as owner shows order" do
      sign_in_as @owner
      get owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
      assert_response :success
    end

    test "GET /owner/restaurants/:id/orders/:id renders successfully for a guest order and shows the guest's name" do
      sign_in_as @owner
      get owner_restaurant_order_path(restaurant_id: @restaurant, id: orders(:guest_order))
      assert_response :success
      assert_match "Jane Diner", response.body
    end

    test "GET /owner/restaurants/:id/orders/:id reads as an itemised docket" do
      sign_in_as @owner
      get owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)

      item = @pending_order.order_items.first
      # One leader row per line, plus the total.
      assert_select ".leader-row", count: @pending_order.order_items.count + 1
      helper = ApplicationController.helpers
      assert_select ".leader-value", text: helper.format_cents(item.subtotal_cents)
      assert_select ".leader-value", text: helper.format_cents(@pending_order.total_amount_cents)
      assert_select "hr.rule-heavy"
      assert_match item.wine.name, response.body
      assert_match "#{item.glass_size_ml}ml", response.body
    end

    test "GET /owner/restaurants/:id/orders/:id names the order's table" do
      table = restaurant_tables(:sala_t1)
      @pending_order.update!(restaurant_table: table)

      sign_in_as @owner
      get owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)

      assert_select ".stamp", text: /#{Regexp.escape(table.name)}/
    end

    test "GET /owner/restaurants/:id/orders/:id offers both actions on a pending order" do
      sign_in_as @owner
      get owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)

      assert_select "form[action=?]", approve_owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
      assert_select "form[action=?]", cancel_owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
    end

    test "GET /owner/restaurants/:id/orders/:id offers no actions on a settled order" do
      sign_in_as @owner
      get owner_restaurant_order_path(restaurant_id: @restaurant, id: @approved_order)

      assert_select "form[action=?]", approve_owner_restaurant_order_path(restaurant_id: @restaurant, id: @approved_order), count: 0
    end

    # --- APPROVE ---

    test "PATCH approve on pending order transitions to approved" do
      sign_in_as @owner
      patch approve_owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
      assert_redirected_to owner_restaurant_orders_path(restaurant_id: @restaurant)
      assert_equal "approved", @pending_order.reload.status
    end

    test "PATCH approve requires authentication" do
      patch approve_owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
      assert_redirected_to sign_in_path
    end

    # --- CANCEL ---

    test "PATCH cancel on pending order transitions to cancelled" do
      sign_in_as @owner
      patch cancel_owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
      assert_redirected_to owner_restaurant_orders_path(restaurant_id: @restaurant)
      assert_equal "cancelled", @pending_order.reload.status
    end

    test "PATCH cancel on approved order transitions to cancelled" do
      sign_in_as @owner
      patch cancel_owner_restaurant_order_path(restaurant_id: @restaurant, id: @approved_order)
      assert_redirected_to owner_restaurant_orders_path(restaurant_id: @restaurant)
      assert_equal "cancelled", @approved_order.reload.status
    end

    test "PATCH cancel requires authentication" do
      patch cancel_owner_restaurant_order_path(restaurant_id: @restaurant, id: @pending_order)
      assert_redirected_to sign_in_path
    end
  end
end
