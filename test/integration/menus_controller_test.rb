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
    # osteria's summer/winter lists are inactive; only osteria_list renders
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_no_match "Summer Selection", response.body
    assert_no_match "Winter Selection", response.body
  end

  test "an active list groups its wines by colour, red before white" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_match "Barolo Riserva", response.body
    assert_match "Gavi di Gavi", response.body

    # osteria_list holds a red (Barolo) and a white (Gavi) wine; the colour
    # sections must render in Wine's color enum order (red: 0, white: 1), not
    # alphabetically or by item position. Anchor on the section ids rather than
    # the colour names — the names also appear in the jump nav above, so
    # matching those would measure nav order instead of render order.
    list_id = wine_lists(:osteria_list).id
    red_index = response.body.index("id=\"list-#{list_id}-red\"")
    white_index = response.body.index("id=\"list-#{list_id}-white\"")
    assert_not_nil red_index
    assert_not_nil white_index
    assert_operator red_index, :<, white_index
  end

  test "deactivating the restaurant's only list shows only the enabled custom lists" do
    wine_lists(:osteria_list).update!(active: false)
    wine_lists(:summer).update!(active: true) # summer holds barolo + sold_out_wine
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_match "Barolo Riserva", response.body      # featured on summer
    assert_no_match "Gavi di Gavi", response.body      # only on the deactivated list
  end

  test "menu is empty when the restaurant's only list is inactive" do
    wine_lists(:osteria_list).update!(active: false)
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_match I18n.t("menu.empty"), response.body
  end

  # --- Table QR entry point (GET /t/:table_token) ---

  test "GET /t/:table_token renders the restaurant menu for a valid token" do
    table = restaurant_tables(:sala_t1)
    get table_menu_path(table_token: table.token)
    assert_response :success
    assert_match "Barolo Riserva", response.body
  end

  test "GET /t/:table_token shows the table name on the menu" do
    table = restaurant_tables(:sala_t1)
    get table_menu_path(table_token: table.token)
    assert_response :success
    assert_match table.name, response.body
  end

  test "GET /t/:table_token stores the table token in the session" do
    table = restaurant_tables(:sala_t1)
    get table_menu_path(table_token: table.token)
    assert_equal table.token, session[:table_tokens][table.restaurant_id.to_s]
  end

  test "scanning a second table replaces the stored token for that restaurant" do
    first = restaurant_tables(:sala_t1)
    second = restaurant_tables(:sala_t2)
    get table_menu_path(table_token: first.token)
    get table_menu_path(table_token: second.token)
    assert_equal second.token, session[:table_tokens][second.restaurant_id.to_s]
  end

  test "tokens from different restaurants are stored independently" do
    osteria_table = restaurant_tables(:sala_t1)
    trattoria_table = restaurant_tables(:trattoria_t1)
    get table_menu_path(table_token: osteria_table.token)
    get table_menu_path(table_token: trattoria_table.token)
    assert_equal osteria_table.token, session[:table_tokens][osteria_table.restaurant_id.to_s]
    assert_equal trattoria_table.token, session[:table_tokens][trattoria_table.restaurant_id.to_s]
  end

  test "GET /t/:table_token with an unknown token returns 404" do
    get table_menu_path(table_token: "no-such-token")
    assert_response :not_found
  end

  test "GET /t/:table_token for an inactive table falls back to the plain menu" do
    table = restaurant_tables(:retired_table)
    get table_menu_path(table_token: table.token)
    assert_response :success
    assert_match "Barolo Riserva", response.body
    assert_no_match table.name, response.body
    assert_nil session[:table_tokens]
  end

  test "GET /t/:table_token for an inactive restaurant returns 404" do
    table = restaurant_tables(:sala_t1)
    table.restaurant.update!(active: false)
    get table_menu_path(table_token: table.token)
    assert_response :not_found
  end

  test "GET /menu/:id still works without any table context" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_nil session[:table_tokens]
  end
end
