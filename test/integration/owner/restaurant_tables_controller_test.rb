require "test_helper"

module Owner
  class RestaurantTablesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
      @table = restaurant_tables(:sala_t1)
    end

    # --- Authorization ---

    test "index requires authentication" do
      get owner_restaurant_tables_path(restaurant_id: @restaurant)
      assert_redirected_to sign_in_path
    end

    test "index as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_restaurant_tables_path(restaurant_id: @restaurant)
      assert_redirected_to root_path
    end

    # --- INDEX / NEW / EDIT ---

    test "index as owner renders tables grouped by area" do
      sign_in_as @owner
      get owner_restaurant_tables_path(restaurant_id: @restaurant)
      assert_response :success
      assert_match "Sala principale", response.body
      assert_match "Dehors", response.body
      assert_match "Tavolo 1", response.body
    end

    test "new as owner renders form" do
      sign_in_as @owner
      get new_owner_restaurant_table_path(restaurant_id: @restaurant)
      assert_response :success
    end

    test "edit as owner renders form" do
      sign_in_as @owner
      get edit_owner_restaurant_table_path(restaurant_id: @restaurant, id: @table)
      assert_response :success
    end

    # --- CREATE ---

    test "create with valid params creates a table with a token" do
      sign_in_as @owner
      assert_difference "RestaurantTable.count", 1 do
        post owner_restaurant_tables_path(restaurant_id: @restaurant), params: {
          restaurant_table: { name: "Tavolo 20", area: "Terrazza", position: 1, active: true }
        }
      end
      assert_redirected_to owner_restaurant_tables_path(restaurant_id: @restaurant)
      table = RestaurantTable.find_by(name: "Tavolo 20")
      assert_equal @restaurant.id, table.restaurant_id
      assert table.token.present?
    end

    test "create with invalid params re-renders new" do
      sign_in_as @owner
      assert_no_difference "RestaurantTable.count" do
        post owner_restaurant_tables_path(restaurant_id: @restaurant), params: {
          restaurant_table: { name: "" }
        }
      end
      assert_response :unprocessable_entity
    end

    test "create ignores a client-supplied token" do
      sign_in_as @owner
      post owner_restaurant_tables_path(restaurant_id: @restaurant), params: {
        restaurant_table: { name: "Tavolo 21", token: "attacker-chosen-token" }
      }
      assert_not_equal "attacker-chosen-token", RestaurantTable.find_by(name: "Tavolo 21").token
    end

    # --- UPDATE ---

    test "update with valid params updates the table" do
      sign_in_as @owner
      patch owner_restaurant_table_path(restaurant_id: @restaurant, id: @table), params: {
        restaurant_table: { name: "Tavolo 1b", active: false }
      }
      assert_redirected_to owner_restaurant_tables_path(restaurant_id: @restaurant)
      @table.reload
      assert_equal "Tavolo 1b", @table.name
      assert_not @table.active?
    end

    test "update with invalid params re-renders edit" do
      sign_in_as @owner
      patch owner_restaurant_table_path(restaurant_id: @restaurant, id: @table), params: {
        restaurant_table: { name: "" }
      }
      assert_response :unprocessable_entity
    end

    # --- DESTROY ---

    test "destroy removes the table" do
      sign_in_as @owner
      assert_difference "RestaurantTable.count", -1 do
        delete owner_restaurant_table_path(restaurant_id: @restaurant, id: @table)
      end
      assert_redirected_to owner_restaurant_tables_path(restaurant_id: @restaurant)
    end

    # --- QR ---

    test "qr renders the table QR code with a valid currentColor fill" do
      sign_in_as @owner
      get qr_owner_restaurant_table_path(restaurant_id: @restaurant, id: @table)
      assert_response :success
      assert_match "<svg", response.body
      assert_match 'fill="currentColor"', response.body
      assert_no_match 'fill="#currentColor"', response.body
      assert_match @table.name, response.body
    end

    test "qr page contains the table menu link" do
      sign_in_as @owner
      get qr_owner_restaurant_table_path(restaurant_id: @restaurant, id: @table)
      assert_match table_menu_path(table_token: @table.token), response.body
    end

    # --- BULK PRINT ---

    # The layout renders many icon <svg>s; QR codes are identified by the
    # crispEdges attribute rqrcode sets on its root element.
    QR_SVG_MARKER = 'shape-rendering="crispEdges"'.freeze

    test "bulk_print renders a QR for every active table" do
      sign_in_as @owner
      get bulk_print_owner_restaurant_tables_path(restaurant_id: @restaurant)
      assert_response :success
      expected = @restaurant.restaurant_tables.active.count
      assert_equal expected, response.body.scan(QR_SVG_MARKER).size
    end

    test "bulk_print filtered by area renders only that area's tables" do
      sign_in_as @owner
      get bulk_print_owner_restaurant_tables_path(restaurant_id: @restaurant, area: "Dehors")
      assert_response :success
      assert_equal 1, response.body.scan(QR_SVG_MARKER).size
      assert_match "Dehors", response.body
    end

    # --- Cross-owner protection ---

    test "cannot access another owner's restaurant tables (404)" do
      sign_in_as @owner
      get owner_restaurant_tables_path(restaurant_id: restaurants(:trattoria))
      assert_response :not_found
    end

    test "cannot view the QR of a table belonging to another owner's restaurant (404)" do
      sign_in_as @owner
      get qr_owner_restaurant_table_path(
        restaurant_id: @restaurant, id: restaurant_tables(:trattoria_t1)
      )
      assert_response :not_found
    end

    # --- BULK NEW / BULK CREATE ---

    test "bulk_new renders the generation form" do
      sign_in_as @owner
      get bulk_new_owner_restaurant_tables_path(@restaurant)
      assert_response :success
    end

    test "index shows the delete-all-tables button when the restaurant has tables" do
      sign_in_as @owner
      get owner_restaurant_tables_path(@restaurant)
      assert_response :success
      assert_match I18n.t("owner.tables.bulk.delete_all"), response.body
    end

    test "index hides the delete-all-tables button when the restaurant has no tables" do
      sign_in_as @owner
      empty_restaurant = restaurants(:inactive_restaurant)
      get owner_restaurant_tables_path(empty_restaurant)
      assert_response :success
      assert_no_match I18n.t("owner.tables.bulk.delete_all"), response.body
    end

    # The delete-all control belongs with the QR-code list, not the generator:
    # owners look for it where the tables they want gone are shown.
    test "bulk_new does not show the delete-all-tables button" do
      sign_in_as @owner
      get bulk_new_owner_restaurant_tables_path(@restaurant)
      assert_response :success
      assert_no_match I18n.t("owner.tables.bulk.delete_all"), response.body
    end

    test "bulk_create generates tables and redirects with notice" do
      sign_in_as @owner
      assert_difference -> { @restaurant.restaurant_tables.count }, 4 do
        post bulk_create_owner_restaurant_tables_path(@restaurant), params: {
          table_bulk_generation: { floors_count: 2, tables_per_floor: 2,
                                   floor_label: "Piano", name_pattern: "t_number" }
        }
      end
      assert_redirected_to owner_restaurant_tables_path(@restaurant)
      assert_equal 303, response.status
    end

    test "bulk_create re-renders with 422 on invalid input" do
      sign_in_as @owner
      assert_no_difference -> { @restaurant.restaurant_tables.count } do
        post bulk_create_owner_restaurant_tables_path(@restaurant), params: {
          table_bulk_generation: { floors_count: 0, tables_per_floor: 2, name_pattern: "t_number" }
        }
      end
      assert_response :unprocessable_entity
    end

    test "bulk actions are scoped to the owner's restaurants" do
      sign_in_as @owner
      get bulk_new_owner_restaurant_tables_path(restaurants(:trattoria))
      assert_response :not_found
      post bulk_create_owner_restaurant_tables_path(restaurants(:trattoria)), params: {
        table_bulk_generation: { floors_count: 1, tables_per_floor: 1, name_pattern: "t_number" }
      }
      assert_response :not_found
    end

    # --- DESTROY ALL ---

    test "destroy_all deletes every table of the owner's restaurant and redirects with notice" do
      sign_in_as @owner
      assert_difference -> { @restaurant.restaurant_tables.count }, -4 do
        delete destroy_all_owner_restaurant_tables_path(@restaurant)
      end
      assert_redirected_to owner_restaurant_tables_path(@restaurant)
      assert_equal 303, response.status
      follow_redirect!
      assert_match I18n.t("owner.tables.bulk.deleted_all", count: 4), response.body
    end

    test "destroy_all does not delete tables belonging to a different restaurant owned by the same user" do
      sign_in_as @owner
      second_restaurant = restaurants(:enoteca)
      other_table = restaurant_tables(:enoteca_t1)
      assert_equal @owner.id, second_restaurant.user_id

      delete destroy_all_owner_restaurant_tables_path(@restaurant)

      assert RestaurantTable.exists?(other_table.id)
      assert_equal second_restaurant.id, other_table.reload.restaurant_id
    end

    test "destroy_all on another user's restaurant is rejected (404)" do
      sign_in_as @owner
      trattoria = restaurants(:trattoria)
      other_table = restaurant_tables(:trattoria_t1)

      assert_no_difference -> { RestaurantTable.count } do
        delete destroy_all_owner_restaurant_tables_path(trattoria)
      end
      assert_response :not_found
      assert RestaurantTable.exists?(other_table.id)
    end

    test "destroy_all nullifies restaurant_table_id on existing orders instead of destroying them" do
      sign_in_as @owner
      order = orders(:pending_order)
      order.update!(restaurant_table: @table)

      delete destroy_all_owner_restaurant_tables_path(@restaurant)

      assert_nil order.reload.restaurant_table_id
    end
  end
end
