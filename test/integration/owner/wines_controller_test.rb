require "test_helper"

module Owner
  class WinesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
      @wine = wines(:barolo)
    end

    # --- Authorization ---

    test "GET /owner/restaurants/:id/wines requires authentication" do
      get owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_redirected_to sign_in_path
    end

    test "GET /owner/restaurants/:id/wines as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_redirected_to root_path
    end

    # --- INDEX ---

    test "GET /owner/restaurants/:id/wines as owner renders index" do
      sign_in_as @owner
      get owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_response :success
    end

    # --- NEW ---

    test "GET /owner/restaurants/:id/wines/new as owner renders new form" do
      sign_in_as @owner
      get new_owner_restaurant_wine_path(restaurant_id: @restaurant)
      assert_response :success
    end

    # --- CREATE ---

    test "POST /owner/restaurants/:id/wines with valid params creates wine" do
      sign_in_as @owner
      assert_difference "Wine.count", 1 do
        post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
          wine: {
            name: "Amarone della Valpolicella",
            producer: "Allegrini",
            grape_variety: "Corvina",
            vintage_year: 2019,
            color: "red",
            region: "Veneto",
            bottle_size_ml: 750,
            price_100ml_cents: 2000,
            price_125ml_cents: 2500,
            available_glasses: 6,
            position: 2,
            active: true
          }
        }
      end
      created = Wine.find_by(name: "Amarone della Valpolicella")
      assert_not_nil created
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
    end

    test "POST /owner/restaurants/:id/wines with invalid params re-renders new form" do
      sign_in_as @owner
      assert_no_difference "Wine.count" do
        post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
          wine: {
            name: "",
            bottle_size_ml: 750,
            available_glasses: 0
          }
        }
      end
      assert_response :unprocessable_entity
    end

    test "POST /owner/restaurants/:id/wines with invalid params wires each error to its field" do
      sign_in_as @owner
      post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
        wine: { name: "", bottle_size_ml: "", available_glasses: -1, price_bottle_cents: 1500 }
      }
      assert_response :unprocessable_entity

      # The summary at the top stays; the inline errors complement it.
      assert_select "div[role=alert] p", minimum: 3

      {
        "wine_name" => "wine_name_error_0",
        "wine_bottle_size_ml" => "wine_bottle_size_ml_error_0",
        "wine_available_glasses" => "wine_available_glasses_hint wine_available_glasses_error_0"
      }.each do |field_id, described_by|
        assert_select "##{field_id}[aria-invalid=?]", "true"
        assert_select "##{field_id}[aria-describedby=?]", described_by
      end

      described_ids = css_select("[aria-describedby]").flat_map { |node| node["aria-describedby"].split }
      css_select("p.field-error").each do |error|
        assert_includes described_ids, error["id"],
          "inline error #{error['id']} is not referenced by any aria-describedby"
      end

      # Fields that validated fine must not claim to be invalid.
      assert_select "#wine_price_bottle_cents[aria-invalid]", false
      assert_select "#wine_region[aria-invalid]", false
    end

    # --- EDIT ---

    test "GET /owner/restaurants/:id/wines/:id/edit as owner renders edit form" do
      sign_in_as @owner
      get edit_owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine)
      assert_response :success
    end

    # --- UPDATE ---

    test "PATCH /owner/restaurants/:id/wines/:id with valid params updates wine" do
      sign_in_as @owner
      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: { name: "Barolo Riserva DOCG" }
      }
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_equal "Barolo Riserva DOCG", @wine.reload.name
    end

    test "PATCH /owner/restaurants/:id/wines/:id with invalid params re-renders edit form" do
      sign_in_as @owner
      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: { name: "", bottle_size_ml: -1 }
      }
      assert_response :unprocessable_entity
    end

    # --- DESTROY ---

    test "DELETE /owner/restaurants/:id/wines/:id destroys wine and redirects" do
      sign_in_as @owner
      # Use sold_out_wine which has no order_items referencing it
      wine_to_delete = wines(:sold_out_wine)
      assert_difference "Wine.count", -1 do
        delete owner_restaurant_wine_path(restaurant_id: @restaurant, id: wine_to_delete)
      end
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
    end

    # --- Cross-owner protection ---

    test "GET /owner/restaurants/:id/wines for another owner's restaurant returns 404" do
      other_owner = User.create!(
        name: "Other Owner",
        email: "other2@example.com",
        password: "password123",
        role: "owner",
        confirmed_at: Time.current
      )
      other_restaurant = other_owner.restaurants.create!(
        name: "Other Place",
        address: "Via Test 2",
        proximity_radius_meters: 100
      )

      sign_in_as @owner
      get owner_restaurant_wines_path(restaurant_id: other_restaurant)
      assert_response :not_found
    end
  end
end
