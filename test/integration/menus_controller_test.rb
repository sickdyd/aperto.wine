require "test_helper"

class MenusControllerTest < ActionDispatch::IntegrationTest
  # GET /menu/:id — active restaurant
  test "GET /menu/:id for active restaurant renders successfully" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success
  end

  test "GET /menu/:id shows active wines for the restaurant" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    # barolo and gavi are active wines for osteria
    assert_match "Barolo Riserva", response.body
    assert_match "Gavi di Gavi", response.body
  end

  # GET /menu/:id — inactive restaurant should return 404
  test "GET /menu/:id for inactive restaurant returns 404" do
    get menu_path(id: restaurants(:inactive_restaurant))
    assert_response :not_found
  end

  # Public: no authentication required
  test "GET /menu/:id is accessible without authentication" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success
  end
end
