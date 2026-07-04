require "test_helper"

module Owner
  class WineListsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
      @wine_list = wine_lists(:summer)
    end

    # --- Authorization ---

    test "index requires authentication" do
      get owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      assert_redirected_to sign_in_path
    end

    test "index as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      assert_redirected_to root_path
    end

    # --- INDEX / NEW / EDIT ---

    test "index as owner renders" do
      sign_in_as @owner
      get owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      assert_response :success
      assert_match "Summer Selection", response.body
    end

    test "new as owner renders form" do
      sign_in_as @owner
      get new_owner_restaurant_wine_list_path(restaurant_id: @restaurant)
      assert_response :success
    end

    test "edit as owner renders form" do
      sign_in_as @owner
      get edit_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)
      assert_response :success
    end

    # --- CREATE ---

    test "create with valid params creates a list" do
      sign_in_as @owner
      assert_difference "WineList.count", 1 do
        post owner_restaurant_wine_lists_path(restaurant_id: @restaurant), params: {
          wine_list: { name: "Reserve", season: "Year-round", position: 3, active: true }
        }
      end
      assert_redirected_to owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      assert_equal @restaurant.id, WineList.find_by(name: "Reserve").restaurant_id
    end

    test "create with invalid params re-renders new" do
      sign_in_as @owner
      assert_no_difference "WineList.count" do
        post owner_restaurant_wine_lists_path(restaurant_id: @restaurant), params: {
          wine_list: { name: "" }
        }
      end
      assert_response :unprocessable_entity
    end

    # --- UPDATE ---

    test "update with valid params updates the list" do
      sign_in_as @owner
      patch owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list), params: {
        wine_list: { name: "Summer 2026", active: false }
      }
      assert_redirected_to owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      @wine_list.reload
      assert_equal "Summer 2026", @wine_list.name
      assert_not @wine_list.active?
    end

    test "update with invalid params re-renders edit" do
      sign_in_as @owner
      patch owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list), params: {
        wine_list: { name: "" }
      }
      assert_response :unprocessable_entity
    end

    # --- DESTROY ---

    test "destroy removes the list" do
      sign_in_as @owner
      assert_difference "WineList.count", -1 do
        delete owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)
      end
      assert_redirected_to owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
    end

    # --- Toggle the default All Wines list ---

    test "toggle_all_wines disables the default list" do
      sign_in_as @owner
      assert @restaurant.all_wines_list_active?
      patch toggle_all_wines_owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      assert_not @restaurant.reload.all_wines_list_active?
      assert_redirected_to owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
    end

    test "toggle_all_wines enables the default list when active is present" do
      @restaurant.update!(all_wines_list_active: false)
      sign_in_as @owner
      patch toggle_all_wines_owner_restaurant_wine_lists_path(restaurant_id: @restaurant),
        params: { active: "1" }
      assert @restaurant.reload.all_wines_list_active?
    end

    test "cannot toggle All Wines for another owner's restaurant (404)" do
      sign_in_as @owner
      patch toggle_all_wines_owner_restaurant_wine_lists_path(restaurant_id: restaurants(:trattoria))
      assert_response :not_found
    end

    # --- Cross-owner protection ---

    test "cannot access another owner's restaurant lists (404)" do
      sign_in_as @owner
      get owner_restaurant_wine_lists_path(restaurant_id: restaurants(:trattoria))
      assert_response :not_found
    end

    test "cannot edit a list belonging to another owner's restaurant (404)" do
      sign_in_as @owner
      get edit_owner_restaurant_wine_list_path(
        restaurant_id: @restaurant, id: wine_lists(:trattoria_list)
      )
      assert_response :not_found
    end
  end
end
