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

  # --- Curated lists ---

  test "renders curated lists when the restaurant has an active list" do
    get menu_path(id: restaurants(:trattoria))
    assert_response :success
    # trattoria_list ("House Picks") is active and curated
    assert_match "House Picks", response.body
    assert_match "Chianti Classico", response.body
  end

  test "a featured but sold-out wine shows as currently unavailable, not hidden" do
    get menu_path(id: restaurants(:trattoria))
    assert_response :success
    # reserve_barbaresco is on the active list but has zero glasses
    assert_match "Reserve Barbaresco", response.body
    assert_match I18n.t("menu.unavailable"), response.body
  end

  test "a deactivated wine on a curated list is hidden, like the flat menu" do
    wines(:chianti).update!(active: false)
    get menu_path(id: restaurants(:trattoria))
    assert_response :success
    assert_no_match "Chianti Classico", response.body
    # An active-but-sold-out wine on the same list still renders (On Deck)
    assert_match "Reserve Barbaresco", response.body
    assert_match I18n.t("menu.unavailable"), response.body
  end

  test "inactive lists are not shown on the public menu" do
    # osteria's summer/winter lists are inactive → menu falls back to flat list
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_no_match "Summer Selection", response.body
    assert_no_match "Winter Selection", response.body
  end

  test "the default All Wines list shows every active wine grouped by color" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_match "Barolo Riserva", response.body
    assert_match "Gavi di Gavi", response.body
  end

  test "disabling All Wines shows only the enabled custom lists" do
    restaurants(:osteria).update!(all_wines_list_active: false)
    wine_lists(:summer).update!(active: true) # summer holds barolo + sold_out_wine
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_match "Barolo Riserva", response.body      # featured on summer
    assert_no_match "Gavi di Gavi", response.body      # only in All Wines, now off
  end

  test "menu is empty when All Wines is off and no custom list is active" do
    restaurants(:osteria).update!(all_wines_list_active: false)
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_match I18n.t("menu.empty"), response.body
  end
end
