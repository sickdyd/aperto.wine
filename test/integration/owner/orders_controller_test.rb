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
