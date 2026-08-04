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

  # A diner who scans a table QR and later follows a plain menu link (e.g.
  # the cart page's "back to menu") must not have that earlier table context
  # resurface here — /menu/:id has never shown table context, and the cart
  # is where remembered-table display belongs (see CartsController).
  test "GET /menu/:id shows no table context even after an earlier table scan this session" do
    table = restaurant_tables(:sala_t1)
    get table_menu_path(table_token: table.token)
    assert_match table.name, response.body

    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_no_match table.name, response.body
  end

  # A retired token's own request must show no table context, even when the
  # session already remembers a *different*, still-active table for the same
  # restaurant from an earlier scan — CustomerScoped#set_restaurant resolves
  # table context from this request's token alone, never from session state
  # left over from a previous visit.
  test "GET /t/:table_token for a retired table never resurrects a previously remembered table" do
    active = restaurant_tables(:sala_t1)
    retired = restaurant_tables(:retired_table)
    get table_menu_path(table_token: active.token)
    assert_match active.name, response.body

    get table_menu_path(table_token: retired.token)
    assert_response :success
    assert_no_match active.name, response.body
    assert_no_match retired.name, response.body
  end

  # --- Add-to-cart controls ---

  test "an available wine renders an add-to-cart control for each priced glass size" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success

    # barolo has 75/100/125ml priced, 150ml explicitly zeroed out
    assert_select "form[action=?][method=post] input[name='wine_id'][value=?]",
      cart_items_path(restaurant_id: restaurants(:osteria)), wines(:barolo).id.to_s, 3
    assert_select "button[aria-label=?]", I18n.t("menu.add_to_cart", wine: wines(:barolo).name, size: 125)
  end

  test "a sold-out wine renders no add-to-cart control" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success

    assert_no_match I18n.t("menu.add_to_cart", wine: wines(:sold_out_wine).name, size: 75), response.body
  end

  test "an unpriced glass size on an available wine renders no control for that size" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success

    # barolo has price_150ml_cents: 0, i.e. not offered at 150ml
    assert_no_match I18n.t("menu.add_to_cart", wine: wines(:barolo).name, size: 150), response.body
  end

  # --- Sticky cart bar ---

  test "the sticky cart bar is absent when the cart is empty" do
    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_select "#cart-bar", false
  end

  test "the sticky cart bar shows the item count and total once the cart has items" do
    post cart_items_path(restaurant_id: restaurants(:osteria)), params: { wine_id: wines(:barolo).id, glass_size_ml: 125, quantity: 2 }

    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_select "#cart-bar"
    assert_match I18n.t("menu.cart_bar.item_count", count: 2), response.body
    assert_match ApplicationController.helpers.format_cents(wines(:barolo).price_for_glass(125) * 2), response.body
  end

  test "the sticky cart bar links to this restaurant's cart page" do
    post cart_items_path(restaurant_id: restaurants(:osteria)), params: { wine_id: wines(:barolo).id, glass_size_ml: 125, quantity: 1 }

    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_select "#cart-bar a[href=?]", cart_path(restaurant_id: restaurants(:osteria))
  end

  test "a restaurant's sticky cart bar never reflects another restaurant's cart" do
    post cart_items_path(restaurant_id: restaurants(:trattoria)), params: { wine_id: wines(:trattoria_franciacorta).id, glass_size_ml: 125, quantity: 1 }

    get menu_path(id: restaurants(:osteria))
    assert_response :success
    assert_select "#cart-bar", false
  end
end
