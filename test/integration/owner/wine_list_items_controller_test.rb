require "test_helper"

module Owner
  class WineListItemsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
      @wine_list = wine_lists(:winter) # has only gavi, so barolo is addable
    end

    # --- Authorization ---

    test "create requires authentication" do
      post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: @wine_list),
        params: { wine_id: wines(:barolo).id }
      assert_redirected_to sign_in_path
    end

    # --- CREATE (add wine to list) ---

    test "adds a wine to the list" do
      sign_in_as @owner
      assert_difference "WineListItem.count", 1 do
        post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: @wine_list),
          params: { wine_id: wines(:barolo).id }
      end
      assert_redirected_to edit_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)
      assert_includes @wine_list.reload.wines, wines(:barolo)
    end

    test "adding a duplicate wine is rejected gracefully" do
      sign_in_as @owner
      assert_no_difference "WineListItem.count" do
        post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: @wine_list),
          params: { wine_id: wines(:gavi).id } # already on winter
      end
      assert_redirected_to edit_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)
      follow_redirect!
      assert_match I18n.t("owner.wine_lists.members.already_added"), response.body
    end

    test "cannot add a wine from another owner's restaurant (404)" do
      sign_in_as @owner
      assert_no_difference "WineListItem.count" do
        post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: @wine_list),
          params: { wine_id: wines(:chianti).id } # belongs to trattoria
      end
      assert_response :not_found
    end

    # --- UPDATE (reorder) ---

    test "updates an item position" do
      sign_in_as @owner
      item = wine_list_items(:winter_gavi)
      patch owner_restaurant_wine_list_wine_list_item_path(restaurant_id: @restaurant, wine_list_id: @wine_list, id: item),
        params: { wine_list_item: { position: 9 } }
      assert_redirected_to edit_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)
      assert_equal 9, item.reload.position
    end

    # --- DESTROY (remove from list) ---

    test "removes an item from the list" do
      sign_in_as @owner
      item = wine_list_items(:winter_gavi)
      assert_difference "WineListItem.count", -1 do
        delete owner_restaurant_wine_list_wine_list_item_path(restaurant_id: @restaurant, wine_list_id: @wine_list, id: item)
      end
      assert_redirected_to edit_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: @wine_list)
      # The wine itself is not destroyed
      assert Wine.exists?(wines(:gavi).id)
    end

    # --- Cross-owner protection on the list itself ---

    test "cannot manage items on another owner's list (404)" do
      sign_in_as @owner
      other_list = wine_lists(:trattoria_list)
      post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: restaurants(:trattoria), wine_list_id: other_list),
        params: { wine_id: wines(:chianti).id }
      assert_response :not_found
    end
  end
end
