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
        wine_list: { name: "Summer 2026" }
      }
      assert_redirected_to owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      @wine_list.reload
      assert_equal "Summer 2026", @wine_list.name
      assert_equal "summer-2026", @wine_list.slug, "the slug follows the name"
    end

    # See the matching test in wines_controller_test — :position is no longer
    # permitted anywhere in the owner area.
    test "update ignores a position submitted in the params" do
      sign_in_as @owner
      original_position = @wine_list.position

      patch owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list), params: {
        wine_list: { name: "Summer 2026", position: 42 }
      }

      assert_redirected_to owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      @wine_list.reload
      assert_equal "Summer 2026", @wine_list.name
      assert_equal original_position, @wine_list.position
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

    # --- PUBLISH ---

    test "publish makes the list the restaurant's public menu" do
      sign_in_as @owner
      patch publish_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)

      assert_redirected_to owner_restaurant_wine_lists_path(restaurant_id: @restaurant)
      assert @wine_list.reload.published?
    end

    test "publish retires the list that was published before" do
      sign_in_as @owner
      incumbent = wine_lists(:osteria_list)

      patch publish_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)

      assert_not incumbent.reload.published?
      assert_equal 1, @restaurant.wine_lists.published.count
    end

    test "publish requires authentication" do
      patch publish_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)

      assert_redirected_to sign_in_path
      assert_not @wine_list.reload.published?
    end

    test "publish as a customer is unauthorized" do
      sign_in_as users(:customer)
      patch publish_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)

      assert_redirected_to root_path
      assert_not @wine_list.reload.published?
    end

    test "cannot publish a list belonging to another owner's restaurant (404)" do
      sign_in_as @owner
      other = wine_lists(:trattoria_reserve)

      patch publish_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: other)

      assert_response :not_found
      assert_not other.reload.published?
    end

    test "a plain update cannot publish a list, bypassing the single-published rule" do
      sign_in_as @owner
      patch owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list), params: {
        wine_list: { name: "Summer Selection", published: true }
      }

      assert_not @wine_list.reload.published?
      assert wine_lists(:osteria_list).reload.published?
    end

    test "a newly created list is not published" do
      sign_in_as @owner
      post owner_restaurant_wine_lists_path(restaurant_id: @restaurant), params: {
        wine_list: { name: "Autumn Selection" }
      }

      created = @restaurant.wine_lists.find_by!(name: "Autumn Selection")
      assert_not created.published?
      assert_equal "autumn-selection", created.slug
      assert wine_lists(:osteria_list).reload.published?, "the live menu is untouched by adding a draft"
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
