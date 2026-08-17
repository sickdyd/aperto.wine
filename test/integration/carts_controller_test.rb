require "test_helper"

class CartsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
    @gavi = wines(:gavi)
    @sold_out = wines(:sold_out_wine)
    @franciacorta = wines(:trattoria_franciacorta)
    @unlisted = wines(:unlisted_wine)
  end

  # Attaches a table to the session the way a diner does, by scanning its QR.
  # Not in setup: several tests below are *about* the tableless state and have
  # to arrive at the bare /menu/:id URL instead. Everything that asserts on
  # the submit control or counts the page's alert bands scans first, because
  # a tableless cart now carries a blocking band of its own and withholds the
  # form — assertions about the stock gate would otherwise pass on the table
  # gate's evidence.
  def scan_table(table = restaurant_tables(:sala_t1))
    get table_menu_path(table_token: table.token)
  end

  # --- add_item ---

  test "adding an item shows it on the cart page" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2 }
    assert_redirected_to published_menu_path(@osteria)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match @barolo.name, response.body
    assert_match @barolo.producer, response.body
  end

  # --- adding from the menu (final review finding 3) ---

  test "a successful add redirects back to the menu, not the cart, with a confirmation flash" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to published_menu_path(@osteria)

    follow_redirect!
    assert_response :success
    assert_match I18n.t("cart.item_added"), response.body
  end

  test "adding a second wine from the menu never requires visiting the cart in between" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to published_menu_path(@osteria)

    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1 }
    assert_redirected_to published_menu_path(@osteria)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match @barolo.name, response.body
    assert_match ERB::Util.html_escape(@gavi.name), response.body
  end

  test "a failed add still redirects to the cart page, where the error has full context" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @sold_out.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
  end

  test "the session survives a real cookie round trip and never stores a price" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2 }
    assert_redirected_to published_menu_path(@osteria)

    get cart_path(restaurant_slug: @osteria.slug)
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
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    post cart_items_path(restaurant_slug: @trattoria.slug), params: { wine_id: @franciacorta.id, serving: "glass", glass_size_ml: 125, quantity: 1 }

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match @barolo.name, response.body
    get cart_path(restaurant_slug: @trattoria.slug)
    assert_match ERB::Util.html_escape(@franciacorta.name), response.body

    delete cart_path(restaurant_slug: @osteria.slug)
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match I18n.t("cart.empty"), response.body
    get cart_path(restaurant_slug: @trattoria.slug)
    assert_match ERB::Util.html_escape(@franciacorta.name), response.body
  end

  test "a wine belonging to another restaurant is rejected" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @franciacorta.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    follow_redirect!
    assert_match I18n.t("cart.errors.wine_not_found"), response.body

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match I18n.t("cart.empty"), response.body
  end

  # A wine that exists, belongs to this restaurant, is active and priced, but
  # was never published on any of the restaurant's active wine lists — the
  # owner's "Published" toggle must gate ordering, not just menu display
  # (Task 6 security fix). Rejected with the same flash as a wine id that
  # doesn't exist at all, so the response never leaks which wines the owner
  # has chosen not to show.
  test "a wine that is not published on any active list is rejected" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @unlisted.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    follow_redirect!
    assert_match I18n.t("cart.errors.wine_not_found"), response.body

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match I18n.t("cart.empty"), response.body
  end

  test "an unavailable wine is rejected with the flash the diner sees" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @sold_out.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    follow_redirect!
    assert_match I18n.t("cart.errors.wine_unavailable"), response.body
  end

  test "an invalid glass size fails cleanly" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 60, quantity: 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    follow_redirect!
    assert_match I18n.t("cart.errors.invalid_glass_size"), response.body
  end

  test "a quantity beyond available stock is rejected with the flash the diner sees" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: @gavi.available_glasses + 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    follow_redirect!
    assert_match I18n.t("cart.errors.insufficient_stock"), response.body
  end

  # A bottle draws on no stock at all (see Wine#bottle_available?), so the
  # quantity that is refused for a pour goes through untouched for a bottle.
  test "a bottle quantity beyond the wine's remaining glasses is accepted" do
    @barolo.update!(available_glasses: 0)
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 3 }
    assert_redirected_to published_menu_path(@osteria)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match @barolo.name, response.body
    assert_no_match I18n.t("cart.errors.insufficient_stock"), response.body
  end

  # --- bottle serving ---

  test "a bottle add shows the wine on the cart page" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 1 }
    assert_redirected_to published_menu_path(@osteria)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match @barolo.name, response.body
  end

  test "a bottle line on the cart page renders the shared bottle label, not a bare size" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 1 }

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("shared.serving.bottle", size: @barolo.bottle_size_ml), response.body
  end

  test "a bottle line and a glass pour of the same wine render as two distinct lines with working controls" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 1 }
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_select "li", text: /#{Regexp.escape(@barolo.name)}/, count: 2
  end

  test "updating a bottle line's quantity from the cart page's own form works" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 1 }
    patch cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 3 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match format_price(@barolo.price_bottle_cents * 3), response.body
  end

  test "removing a bottle line from the cart page works" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 1 }
    delete cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle" }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_no_match @barolo.name, response.body
    assert_match I18n.t("cart.empty"), response.body
  end

  # A bottle and a glass pour of the same wine must not collide: removing
  # the bottle line must leave the glass line (and its own quantity) intact.
  test "removing a bottle line does not disturb a coexisting glass line for the same wine" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle", quantity: 1 }
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2 }

    delete cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "bottle" }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_no_match I18n.t("shared.serving.bottle", size: @barolo.bottle_size_ml), response.body
    assert_match format_price(@barolo.price_for_glass(125) * 2), response.body
  end

  test "a dropped bottle line whose wine was deleted renders the bottle-specific remove label, with no size interpolated" do
    doomed_wine = @osteria.wines.create!(
      name: "Doomed Bottle Wine", color: :red, bottle_size_ml: 750,
      price_bottle_cents: 5000, available_glasses: 5, active: true, position: 992
    )
    wine_lists(:osteria_list).wine_list_items.create!(wine: doomed_wine, position: doomed_wine.position)
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: doomed_wine.id, serving: "bottle", quantity: 1 }
    doomed_wine.destroy!

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_select "button[aria-label=?]", I18n.t("cart.dropped_item.remove_unknown_bottle", wine_id: doomed_wine.id)

    # End-to-end removability: the rendered button is not just cosmetic — a
    # diner stuck with an unremovable line has a dead cart, so the delete it
    # posts must actually clear the dropped line, not just render.
    delete cart_items_path(restaurant_slug: @osteria.slug),
      params: { wine_id: doomed_wine.id, serving: "bottle" }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("cart.empty"), response.body
    assert_no_match I18n.t("cart.dropped_items_notice"), response.body
  end

  test "an add with a bad serving fails cleanly and adds nothing to the cart" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "keg", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    follow_redirect!
    assert_match I18n.t("cart.errors.invalid_serving"), response.body

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match I18n.t("cart.empty"), response.body
  end

  # --- stale pre-deploy forms with no serving field at all ---
  #
  # A diner's already-open menu tab, rendered before this deploy, posts an
  # add with no "serving" key in the request body whatsoever — not blank,
  # entirely absent. That must keep working as a glass add (see
  # CartsController#serving_param), unlike a request that names the key and
  # gets it wrong.

  test "an add with the serving key entirely absent from the request is treated as a glass" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 1 }
    assert_redirected_to published_menu_path(@osteria)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match @barolo.name, response.body
  end

  test "an add with a present but blank serving still fails as invalid, unlike an absent one" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "", glass_size_ml: 125, quantity: 1 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)
    follow_redirect!
    assert_match I18n.t("cart.errors.invalid_serving"), response.body

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match I18n.t("cart.empty"), response.body
  end

  # --- Flash layout (Task 5, Part E regression fix) ---

  test "the cart page's error flash renders exactly once, in the floating stack" do
    # The table is scanned so the cart page has no second alert to render:
    # without one it also announces that ordering needs a table, and this
    # test is counting alerts.
    scan_table
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 60, quantity: 1 }
    follow_redirect!

    assert_select "[role='alert']", 1
    assert_select "div.toast-stack [role='alert']", 1
  end

  test "a missing wine_id fails cleanly, not with a 500" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { glass_size_ml: 125, quantity: 1 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "a non-numeric wine_id fails cleanly, not with a 500" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: "not-a-number", serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "a non-numeric glass_size_ml fails cleanly, not with a 500" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: "big", quantity: 1 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "a missing quantity defaults cleanly rather than 500ing" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125 }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  # --- update_item / remove_item ---

  test "updating quantity changes the subtotal shown on the cart page" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    patch cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match format_price(@barolo.price_for_glass(125) * 3), response.body
  end

  test "removing an item takes it off the cart page" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    delete cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_no_match @barolo.name, response.body
    assert_match I18n.t("cart.empty"), response.body
  end

  test "updating quantity with the serving key entirely absent still finds the glass line" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    patch cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, glass_size_ml: 125, quantity: 3 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_match format_price(@barolo.price_for_glass(125) * 3), response.body
  end

  test "removing an item with the serving key entirely absent still finds the glass line" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    delete cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, glass_size_ml: 125 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_no_match @barolo.name, response.body
    assert_match I18n.t("cart.empty"), response.body
  end

  # --- inactive restaurant ---

  test "an inactive restaurant 404s on every cart action" do
    inactive = restaurants(:inactive_restaurant)

    get cart_path(restaurant_slug: inactive.slug)
    assert_response :not_found

    post cart_items_path(restaurant_slug: inactive.slug), params: { wine_id: 1, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_response :not_found

    patch cart_items_path(restaurant_slug: inactive.slug), params: { wine_id: 1, serving: "glass", glass_size_ml: 125, quantity: 1 }
    assert_response :not_found

    delete cart_items_path(restaurant_slug: inactive.slug), params: { wine_id: 1, serving: "glass", glass_size_ml: 125 }
    assert_response :not_found

    delete cart_path(restaurant_slug: inactive.slug)
    assert_response :not_found
  end

  # --- table context ---

  test "the cart page names the table for a diner who arrived via /t/:table_token" do
    table = restaurant_tables(:sala_t1)
    get table_menu_path(table_token: table.token)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match table.name, response.body
  end

  test "the cart page renders without a table for a diner who arrived via /menu/:id" do
    get published_menu_path(@osteria)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("cart.no_table_context"), response.body
  end

  # PlaceOrder refuses a tableless placement outright, so the page must not
  # offer a control that can only fail — and must say why where the diner
  # reads it while building the order, not after trying to send it.
  test "a tableless cart withholds the submit control and says why" do
    get published_menu_path(@osteria)
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_select "button", text: I18n.t("orders.form.submit"), count: 0
    assert_match ERB::Util.html_escape(I18n.t("cart.no_table_context")), response.body
    # Not the empty state either — the order is built, it just has nowhere to go.
    assert_no_match I18n.t("cart.empty"), response.body
    assert_match @barolo.name, response.body
  end

  test "scanning a table brings the submit control back to a cart built without one" do
    get published_menu_path(@osteria)
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    scan_table

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_select "button", text: I18n.t("orders.form.submit"), count: 1
    assert_no_match ERB::Util.html_escape(I18n.t("cart.no_table_context")), response.body
  end

  test "a retired table's token attaches no table to the cart" do
    table = restaurant_tables(:retired_table)
    get table_menu_path(table_token: table.token)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_no_match table.name, response.body
    assert_match I18n.t("cart.no_table_context"), response.body
  end

  # --- dropped items ---

  test "an item that becomes unavailable after being added is reported to the diner" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    @barolo.update!(active: false)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("cart.dropped_items_notice"), response.body
  end

  # --- recovering from a dropped line (final review finding 1) ---

  test "the dropped-items notice never claims items have already been removed" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    @barolo.update!(active: false)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_no_match "have been removed", response.body
  end

  test "a dropped line renders its own name and a remove control" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    @barolo.update!(active: false)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match @barolo.name, response.body
    assert_select "form[action=?][method=post] button[aria-label=?]",
      cart_items_path(restaurant_slug: @osteria.slug), I18n.t("cart.remove_item", wine: @barolo.name)
  end

  test "a cart whose only line has been dropped still offers the Empty cart control" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    @barolo.update!(active: false)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    # Reproduces the bricked-cart bug: items 0, dropped_items 1, empty? true —
    # the "Empty cart" button must still render even though the old `unless
    # @cart.empty?` branch would have hidden it.
    assert cart_for(@osteria).empty?
    assert_select "button", text: I18n.t("cart.clear_cart"), count: 1
  end

  test "a diner can remove a dropped line, recovering a cart that would otherwise be stuck forever" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    @barolo.update!(active: false)

    delete cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125 }
    assert_redirected_to cart_path(restaurant_slug: @osteria.slug)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("cart.empty"), response.body
    assert_no_match I18n.t("cart.dropped_items_notice"), response.body
  end

  test "a wine whose price falls to zero after being added is treated as dropped, not silently blanked out" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1 }
    @gavi.update!(price_100ml_cents: 0)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match I18n.t("cart.dropped_items_notice"), response.body
    assert_match ERB::Util.html_escape(@gavi.name), response.body
  end

  # --- stock that fell away under a cart that was already valid (Task 4) ---
  #
  # Every case here is the same shape: a line the cart happily accepted, whose
  # wine then lost glasses to somebody else's order. The wine is still on the
  # menu and still has a price, so the line is *not* dropped — it is merely
  # too large, and the diner fixes it with the stepper the line already has.

  test "a line whose wine lost stock after it was added is flagged rather than dropped" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3 }
    @barolo.update!(available_glasses: 2)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_match ERB::Util.html_escape(I18n.t("cart.stock_shortfall_notice")), response.body
    assert_no_match I18n.t("cart.dropped_items_notice"), response.body
    # Normal treatment kept: the line still carries the control that fixes it.
    assert_select "select#cart_item_#{@barolo.id}_glass_125_quantity", 1
  end

  test "the shortfall banner is an alert, and a different one from the dropped-items band" do
    scan_table
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3 }
    @barolo.update!(available_glasses: 2)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_select "[role='alert'].alert-info", 1
    assert_select "[role='alert'].alert-warning", 0
  end

  test "the shortfall note names what is left and is associated with that line's quantity control" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3 }
    @barolo.update!(available_glasses: 2)

    get cart_path(restaurant_slug: @osteria.slug)
    note_id = "cart_item_#{@barolo.id}_glass_125_stock"
    assert_select "p##{note_id}", text: I18n.t("cart.stock_shortfall", count: 2)
    assert_select "select#cart_item_#{@barolo.id}_glass_125_quantity[aria-describedby=?]", note_id
  end

  # One wine at two glass sizes draws on one pool of glasses, so both lines are
  # over stock together and the note states the wine's remaining total on each
  # — it is a fact about the wine, not about the row.
  test "the same wine at two glass sizes flags both of its lines" do
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2 }
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 100, quantity: 2 }
    @barolo.update!(available_glasses: 3)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    [ 125, 100 ].each do |size|
      assert_select "p#cart_item_#{@barolo.id}_glass_#{size}_stock", text: I18n.t("cart.stock_shortfall", count: 3)
    end
  end

  test "the submit control is withheld while a line exceeds stock, without falling back to the empty state" do
    scan_table
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3 }
    @barolo.update!(available_glasses: 2)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_select "button", text: I18n.t("orders.form.submit"), count: 0
    assert_no_match I18n.t("cart.empty"), response.body
    assert_match ERB::Util.html_escape(@barolo.name), response.body
  end

  # The same gate covers the older blocker: a dropped line aborts the whole
  # placement in PlaceOrder, so offering a submit that can only fail is worse
  # than withholding it until the line is gone.
  test "the submit control is withheld while a dropped line still needs removing" do
    scan_table
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1 }
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @gavi.id, glass_size_ml: 100, quantity: 1 }
    @barolo.update!(active: false)

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_select "button", text: I18n.t("orders.form.submit"), count: 0
  end

  test "lowering the quantity to what is left brings the submit control back" do
    scan_table
    post cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3 }
    @barolo.update!(available_glasses: 2)
    patch cart_items_path(restaurant_slug: @osteria.slug), params: { wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2 }

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_no_match ERB::Util.html_escape(I18n.t("cart.stock_shortfall_notice")), response.body
    assert_select "button", text: I18n.t("orders.form.submit"), count: 1
  end

  private

  def cart_for(restaurant)
    Cart.new(session: session, restaurant: restaurant)
  end

  def format_price(cents)
    ApplicationController.helpers.format_cents(cents)
  end
end
