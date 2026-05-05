require "test_helper"

module Owner
  class RestaurantsControllerTest < ActionDispatch::IntegrationTest
    # --- Authorization ---

    test "GET /owner/restaurants requires authentication" do
      get owner_restaurants_path
      assert_redirected_to sign_in_path
    end

    test "GET /owner/restaurants as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_restaurants_path
      assert_redirected_to root_path
    end

    # --- INDEX ---

    test "GET /owner/restaurants as owner renders index" do
      sign_in_as users(:owner)
      get owner_restaurants_path
      assert_response :success
    end

    test "GET /owner/restaurants as admin renders index" do
      sign_in_as users(:admin)
      get owner_restaurants_path
      assert_response :success
    end

    # --- SHOW ---

    test "GET /owner/restaurants/:id as owner shows restaurant" do
      sign_in_as users(:owner)
      get owner_restaurant_path(id: restaurants(:osteria))
      assert_response :success
    end

    test "GET /owner/restaurants/:id belonging to another user returns 404" do
      other_owner = User.create!(
        name: "Other Owner",
        email: "other_owner@example.com",
        password: "password123",
        role: "owner",
        confirmed_at: Time.current
      )
      other_restaurant = other_owner.restaurants.create!(
        name: "Other Place",
        address: "Via Test 1",
        proximity_radius_meters: 100
      )

      sign_in_as users(:owner)
      get owner_restaurant_path(id: other_restaurant)
      assert_response :not_found
    end

    # --- NEW ---

    test "GET /owner/restaurants/new as owner renders new form" do
      sign_in_as users(:owner)
      get new_owner_restaurant_path
      assert_response :success
    end

    # --- CREATE ---

    test "POST /owner/restaurants with valid params creates restaurant" do
      sign_in_as users(:owner)
      assert_difference "Restaurant.count", 1 do
        post owner_restaurants_path, params: {
          restaurant: {
            name: "Trattoria Bella",
            address: "Via Napoli 10, Napoli",
            description: "Neapolitan food",
            proximity_radius_meters: 150,
            active: true
          }
        }
      end
      created = Restaurant.find_by(name: "Trattoria Bella")
      assert_not_nil created
      assert_redirected_to owner_restaurant_path(id: created)
    end

    test "POST /owner/restaurants with invalid params re-renders new form" do
      sign_in_as users(:owner)
      assert_no_difference "Restaurant.count" do
        post owner_restaurants_path, params: {
          restaurant: {
            name: "",
            address: "",
            proximity_radius_meters: 0
          }
        }
      end
      assert_response :unprocessable_entity
    end

    # --- EDIT ---

    test "GET /owner/restaurants/:id/edit as owner renders edit form" do
      sign_in_as users(:owner)
      get edit_owner_restaurant_path(id: restaurants(:osteria))
      assert_response :success
    end

    # --- UPDATE ---

    test "PATCH /owner/restaurants/:id with valid params updates restaurant" do
      sign_in_as users(:owner)
      patch owner_restaurant_path(id: restaurants(:osteria)), params: {
        restaurant: { name: "Osteria Aggiornata" }
      }
      assert_redirected_to owner_restaurant_path(id: restaurants(:osteria))
      assert_equal "Osteria Aggiornata", restaurants(:osteria).reload.name
    end

    test "PATCH /owner/restaurants/:id with invalid params re-renders edit form" do
      sign_in_as users(:owner)
      patch owner_restaurant_path(id: restaurants(:osteria)), params: {
        restaurant: { name: "", address: "" }
      }
      assert_response :unprocessable_entity
    end

    # --- DESTROY ---

    test "DELETE /owner/restaurants/:id destroys restaurant and redirects" do
      # Use inactive_restaurant which has no orders or wines referencing order_items
      sign_in_as users(:owner)
      assert_difference "Restaurant.count", -1 do
        delete owner_restaurant_path(id: restaurants(:inactive_restaurant))
      end
      assert_redirected_to owner_restaurants_path
    end
  end
end
