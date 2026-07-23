require "test_helper"

module Owner
  class WineListItemsControllerTest < ActionDispatch::IntegrationTest
    TURBO_STREAM_ACCEPT = "text/vnd.turbo-stream.html"

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

    test "adds a wine to the list via turbo_stream" do
      sign_in_as @owner
      assert_difference "WineListItem.count", 1 do
        post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: @wine_list),
          params: { wine_id: wines(:barolo).id },
          headers: { "Accept" => TURBO_STREAM_ACCEPT }
      end
      assert_response :success
      assert_equal Mime[:turbo_stream], response.media_type
      assert_match "wine_list_members", response.body
      assert_match wines(:barolo).name, response.body
    end

    test "duplicate wine via turbo_stream does not create a record and still responds successfully" do
      sign_in_as @owner
      assert_no_difference "WineListItem.count" do
        post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: @wine_list),
          params: { wine_id: wines(:gavi).id }, # already on winter
          headers: { "Accept" => TURBO_STREAM_ACCEPT }
      end
      assert_response :success
      assert_equal Mime[:turbo_stream], response.media_type
      assert_match "wine_list_members", response.body
      assert_match I18n.t("owner.wine_lists.members.already_added"), response.body
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

    test "updates an item position via turbo_stream" do
      sign_in_as @owner
      item = wine_list_items(:winter_gavi)
      patch owner_restaurant_wine_list_wine_list_item_path(restaurant_id: @restaurant, wine_list_id: @wine_list, id: item),
        params: { wine_list_item: { position: 9 } },
        headers: { "Accept" => TURBO_STREAM_ACCEPT }
      assert_response :success
      assert_equal Mime[:turbo_stream], response.media_type
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

    test "removes an item from the list via turbo_stream" do
      sign_in_as @owner
      item = wine_list_items(:winter_gavi)
      assert_difference "WineListItem.count", -1 do
        delete owner_restaurant_wine_list_wine_list_item_path(restaurant_id: @restaurant, wine_list_id: @wine_list, id: item),
          headers: { "Accept" => TURBO_STREAM_ACCEPT }
      end
      assert_response :success
      assert_equal Mime[:turbo_stream], response.media_type
    end

    # --- Cross-owner protection on the list itself ---

    test "cannot manage items on another owner's list (404)" do
      sign_in_as @owner
      other_list = wine_lists(:trattoria_list)
      post owner_restaurant_wine_list_wine_list_items_path(restaurant_id: restaurants(:trattoria), wine_list_id: other_list),
        params: { wine_id: wines(:chianti).id }
      assert_response :not_found
    end

    # --- SORT (bulk reorder) ---

    test "sort reorders positions to match submitted order" do
      sign_in_as @owner
      # summer list has two items: summer_barolo (pos 1), summer_sold_out (pos 2)
      first = wine_list_items(:summer_barolo)
      second = wine_list_items(:summer_sold_out)
      summer = wine_lists(:summer)

      patch sort_owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: summer),
        params: { item_ids: [ second.id, first.id ] }

      assert_redirected_to edit_owner_restaurant_wine_list_path(restaurant_id: @restaurant, id: summer)
      assert_equal 1, second.reload.position
      assert_equal 2, first.reload.position
    end

    test "sort via turbo_stream-style request responds head :ok" do
      sign_in_as @owner
      first = wine_list_items(:summer_barolo)
      second = wine_list_items(:summer_sold_out)
      summer = wine_lists(:summer)

      patch sort_owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: summer),
        params: { item_ids: [ second.id, first.id ] },
        headers: { "Accept" => TURBO_STREAM_ACCEPT }

      assert_response :ok
      assert_empty response.body
      assert_equal 1, second.reload.position
      assert_equal 2, first.reload.position
    end

    test "sort with an id from another list on the same restaurant is rejected (404)" do
      sign_in_as @owner
      other_list_item = wine_list_items(:summer_barolo) # belongs to :summer, not :winter
      winter_item = wine_list_items(:winter_gavi)
      original_position = other_list_item.position

      patch sort_owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: @wine_list),
        params: { item_ids: [ winter_item.id, other_list_item.id ] }

      assert_response :not_found
      assert_equal original_position, other_list_item.reload.position
    end

    test "sort for a restaurant the signed-in owner does not own is rejected (404)" do
      sign_in_as @owner
      trattoria_list = wine_lists(:trattoria_list)
      item = wine_list_items(:trattoria_chianti)

      patch sort_owner_restaurant_wine_list_wine_list_items_path(restaurant_id: restaurants(:trattoria), wine_list_id: trattoria_list),
        params: { item_ids: [ item.id ] }

      assert_response :not_found
    end

    test "sort with empty item_ids is unprocessable" do
      sign_in_as @owner
      summer = wine_lists(:summer)

      patch sort_owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: summer),
        params: { item_ids: [] }

      assert_response :unprocessable_entity
    end

    test "sort with missing item_ids is unprocessable" do
      sign_in_as @owner
      summer = wine_lists(:summer)

      patch sort_owner_restaurant_wine_list_wine_list_items_path(restaurant_id: @restaurant, wine_list_id: summer)

      assert_response :unprocessable_entity
    end
  end
end
