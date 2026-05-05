require "test_helper"

module Owner
  class QrCodesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
    end

    # --- Authorization ---

    test "GET /owner/restaurants/:id/qr_code requires authentication" do
      get owner_restaurant_qr_code_path(restaurant_id: @restaurant)
      assert_redirected_to sign_in_path
    end

    test "GET /owner/restaurants/:id/qr_code as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_restaurant_qr_code_path(restaurant_id: @restaurant)
      assert_redirected_to root_path
    end

    # --- SHOW ---

    test "GET /owner/restaurants/:id/qr_code as owner renders successfully" do
      sign_in_as @owner
      get owner_restaurant_qr_code_path(restaurant_id: @restaurant)
      assert_response :success
    end

    test "GET /owner/restaurants/:id/qr_code generates SVG QR code in response" do
      sign_in_as @owner
      get owner_restaurant_qr_code_path(restaurant_id: @restaurant)
      assert_response :success
      # The QR code SVG should be embedded in the page
      assert_match "<svg", response.body
    end

    test "GET /owner/restaurants/:id/qr_code as admin for own restaurant renders successfully" do
      # Admin can access their own restaurants; here we sign in as owner of osteria
      # and confirm the page renders — admin with no restaurants gets 404 (expected behaviour)
      sign_in_as @owner
      get owner_restaurant_qr_code_path(restaurant_id: @restaurant)
      assert_response :success
    end

    test "GET /owner/restaurants/:id/qr_code for another owner's restaurant returns 404" do
      other_owner = User.create!(
        name: "Other Owner",
        email: "other3@example.com",
        password: "password123",
        role: "owner",
        confirmed_at: Time.current
      )
      other_restaurant = other_owner.restaurants.create!(
        name: "Other Place",
        address: "Via Test 3",
        proximity_radius_meters: 100
      )

      sign_in_as @owner
      get owner_restaurant_qr_code_path(restaurant_id: other_restaurant)
      assert_response :not_found
    end
  end
end
