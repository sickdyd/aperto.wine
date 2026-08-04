require "test_helper"

class CartsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
    @gavi = wines(:gavi)
    @sold_out = wines(:sold_out_wine)
    @barbera = wines(:trattoria_barbera)
  end

  # --- add_item ---

  test "adding an item shows it on the cart page" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 2 }
    assert_redirected_to cart_path(restaurant_id: @osteria)

    get cart_path(restaurant_id: @osteria)
    assert_response :success
    assert_match @barolo.name, response.body
    assert_match @barolo.producer, response.body
  end

  test "the session survives a real cookie round trip and never stores a price" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 2 }
    assert_redirected_to cart_path(restaurant_id: @osteria)

    get cart_path(restaurant_id: @osteria)
    assert_response :success
    assert_match @barolo.name, response.body

    lines = session[:carts][@osteria.id.to_s]
    assert_equal 1, lines.size
    assert_equal @barolo.id, lines.first["wine_id"]
    assert_equal 125, lines.first["glass_size_ml"]
    assert_equal 2, lines.first["quantity"]
    assert_not lines.first.key?("price_cents")
    assert_not lines.first.to_s.include?("price")
  end

  test "two restaurants' carts stay independent, and clearing one leaves the other intact" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 1 }
    post cart_items_path(restaurant_id: @trattoria), params: { wine_id: @barbera.id, glass_size_ml: 125, quantity: 1 }

    get cart_path(restaurant_id: @osteria)
    assert_match @barolo.name, response.body
    get cart_path(restaurant_id: @trattoria)
    assert_match ERB::Util.html_escape(@barbera.name), response.body

    delete cart_path(restaurant_id: @osteria)
    assert_redirected_to cart_path(restaurant_id: @osteria)

    get cart_path(restaurant_id: @osteria)
    assert_match I18n.t("cart.empty"), response.body
    get cart_path(restaurant_id: @trattoria)
    assert_match ERB::Util.html_escape(@barbera.name), response.body
  end

  test "a wine belonging to another restaurant is rejected" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barbera.id, glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_id: @osteria)
    follow_redirect!
    assert_match I18n.t("cart.errors.wine_not_found"), response.body

    get cart_path(restaurant_id: @osteria)
    assert_match I18n.t("cart.empty"), response.body
  end

  test "an unavailable wine is rejected with the flash the diner sees" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @sold_out.id, glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_id: @osteria)
    follow_redirect!
    assert_match I18n.t("cart.errors.wine_unavailable"), response.body
  end

  test "an invalid glass size fails cleanly" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 60, quantity: 1 }
    assert_redirected_to cart_path(restaurant_id: @osteria)
    follow_redirect!
    assert_match I18n.t("cart.errors.invalid_glass_size"), response.body
  end

  # --- Flash layout (Task 5, Part E regression fix) ---

  test "the cart page's error flash renders exactly once, at the page's own width" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 60, quantity: 1 }
    follow_redirect!

    assert_select "[role='alert']", 1
    assert_select "div.max-w-2xl [role='alert']", 1
  end

  test "a missing wine_id fails cleanly, not with a 500" do
    post cart_items_path(restaurant_id: @osteria), params: { glass_size_ml: 125, quantity: 1 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "a non-numeric wine_id fails cleanly, not with a 500" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: "not-a-number", glass_size_ml: 125, quantity: 1 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "a non-numeric glass_size_ml fails cleanly, not with a 500" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: "big", quantity: 1 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "a missing quantity defaults cleanly rather than 500ing" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  # --- update_item / remove_item ---

  test "updating quantity changes the subtotal shown on the cart page" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 1 }
    patch cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 3 }
    assert_redirected_to cart_path(restaurant_id: @osteria)

    get cart_path(restaurant_id: @osteria)
    assert_match format_price(@barolo.price_for_glass(125) * 3), response.body
  end

  test "removing an item takes it off the cart page" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 1 }
    delete cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125 }
    assert_redirected_to cart_path(restaurant_id: @osteria)

    get cart_path(restaurant_id: @osteria)
    assert_no_match @barolo.name, response.body
    assert_match I18n.t("cart.empty"), response.body
  end

  # --- inactive restaurant ---

  test "an inactive restaurant 404s on every cart action" do
    inactive = restaurants(:inactive_restaurant)

    get cart_path(restaurant_id: inactive)
    assert_response :not_found

    post cart_items_path(restaurant_id: inactive), params: { wine_id: 1, glass_size_ml: 125, quantity: 1 }
    assert_response :not_found

    patch cart_items_path(restaurant_id: inactive), params: { wine_id: 1, glass_size_ml: 125, quantity: 1 }
    assert_response :not_found

    delete cart_items_path(restaurant_id: inactive), params: { wine_id: 1, glass_size_ml: 125 }
    assert_response :not_found

    delete cart_path(restaurant_id: inactive)
    assert_response :not_found
  end

  # --- table context ---

  test "the cart page names the table for a diner who arrived via /t/:table_token" do
    table = restaurant_tables(:sala_t1)
    get table_menu_path(table_token: table.token)

    get cart_path(restaurant_id: @osteria)
    assert_response :success
    assert_match table.name, response.body
  end

  test "the cart page renders without a table for a diner who arrived via /menu/:id" do
    get menu_path(id: @osteria)

    get cart_path(restaurant_id: @osteria)
    assert_response :success
    assert_match I18n.t("cart.no_table_context"), response.body
  end

  test "a retired table's token attaches no table to the cart" do
    table = restaurant_tables(:retired_table)
    get table_menu_path(table_token: table.token)

    get cart_path(restaurant_id: @osteria)
    assert_response :success
    assert_no_match table.name, response.body
    assert_match I18n.t("cart.no_table_context"), response.body
  end

  # --- dropped items ---

  test "an item that becomes unavailable after being added is reported to the diner" do
    post cart_items_path(restaurant_id: @osteria), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 1 }
    @barolo.update!(active: false)

    get cart_path(restaurant_id: @osteria)
    assert_response :success
    assert_match I18n.t("cart.dropped_items_notice"), response.body
  end

  private

  def format_price(cents)
    ApplicationController.helpers.format_cents(cents)
  end
end
