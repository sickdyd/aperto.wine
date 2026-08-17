require "application_system_test_case"

class WineOrderingTest < ApplicationSystemTestCase
  # Clicks the add-to-cart control for one wine at one glass size. The
  # control's visible text is aria-hidden (see menus/_wine_row) — its
  # accessible name is the wine + size aria-label alone — so this locates
  # by that aria-label rather than by visible text.
  def add_to_cart(wine, size)
    find("button[aria-label='#{I18n.t("menu.add_to_cart", wine: wine.name, size: size)}']").click
  end

  # Every remove control's accessible name comes entirely from aria-label
  # (see carts/_cart_item and _dropped_cart_item) — Capybara's click_button
  # does not match on aria-label by default, so this locates by the
  # attribute directly, mirroring #add_to_cart above.
  def remove_from_cart(label)
    find("button[aria-label='#{label}']").click
  end

  # Clicks the bottle add-to-cart control for one wine — the bottle
  # equivalent of #add_to_cart above. See menus/_wine_row: its aria-label
  # names the wine and reuses shared.serving.bottle for the serving half.
  def add_bottle_to_cart(wine)
    bottle_label = I18n.t("shared.serving.bottle", size: wine.bottle_size_ml)
    find("button[aria-label='#{I18n.t("menu.add_to_cart_bottle", wine: wine.name, bottle_label: bottle_label)}']").click
  end

  # A successful add redirects back to the menu (final review finding 3),
  # so getting to the cart page from there is always a deliberate extra
  # step via the sticky bar's link.
  def go_to_cart
    within "#cart-bar" do
      click_link I18n.t("menu.cart_bar.view_cart")
    end
  end

  def format_price(cents)
    ApplicationController.helpers.format_cents(cents)
  end

  # The ledger sets its mono labels, chips and status badges in small caps
  # with CSS `text-transform`, and WebDriver reports *rendered* text — so a
  # literal assertion on the translated string now fails on casing alone,
  # for a string the DOM still holds verbatim. Casing is presentation here,
  # so assert on the words and let the stylesheet own the case. Everything
  # else about the assertion (visibility, waiting, scoping) is unchanged.
  def assert_recased_text(text, **options)
    assert_text(/#{Regexp.escape(text)}/i, **options)
  end

  def sign_in_as_owner(owner)
    visit sign_in_path
    fill_in "email", with: owner.email
    fill_in "password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_current_path owner_restaurants_path, wait: 5
  end

  test "the whole guest journey: table QR, sticky bar, cart, and status page" do
    restaurant = restaurants(:osteria)
    table = restaurant_tables(:sala_t1)
    barolo = wines(:barolo)
    gavi = wines(:gavi)

    visit table_menu_path(table_token: table.token)
    assert_text barolo.name, wait: 5

    # Adding lands back on the menu (CartsController#add_item's redirect),
    # so both wines can be added one after another with no navigation in
    # between.
    add_to_cart(barolo, 125) # a non-default glass size
    assert_current_path published_menu_path(restaurant), wait: 5
    add_to_cart(gavi, 100)
    assert_current_path published_menu_path(restaurant), wait: 5

    assert_selector "#cart-bar", wait: 5
    within "#cart-bar" do
      assert_recased_text I18n.t("menu.cart_bar.item_count", count: 2)
      assert_text format_price(barolo.price_for_glass(125) + gavi.price_for_glass(100))
    end
    go_to_cart

    assert_current_path cart_path(restaurant_slug: restaurant.slug), wait: 5

    # Bump barolo from 1 to 2 glasses. Each cart line is one <li> of the
    # bill's ruled list (see carts/_cart_item).
    within(find("li", text: barolo.name)) do
      select "2", from: "cart_item_#{barolo.id}_glass_125_quantity"
      click_button I18n.t("cart.update_quantity")
    end

    expected_total = (barolo.price_for_glass(125) * 2) + gavi.price_for_glass(100)
    assert_text format_price(expected_total), wait: 5

    fill_in I18n.t("orders.form.guest_name"), with: "System Test Diner"
    click_button I18n.t("orders.form.submit")

    assert_text I18n.t("orders.status.statuses.pending"), wait: 5
    assert_text barolo.name
    assert_text gavi.name
    assert_text format_price(expected_total)
    assert_text table.name
  end

  test "carts stay isolated per restaurant in the same browser" do
    osteria = restaurants(:osteria)
    trattoria = restaurants(:trattoria)
    barolo = wines(:barolo)

    visit restaurant_menu_path(restaurant_slug: osteria.slug)
    add_to_cart(barolo, 125)
    assert_current_path published_menu_path(osteria), wait: 5
    assert_selector "#cart-bar", wait: 5

    visit restaurant_menu_path(restaurant_slug: trattoria.slug)
    assert_no_selector "#cart-bar", wait: 5
    visit cart_path(restaurant_slug: trattoria.slug)
    assert_text I18n.t("cart.empty"), wait: 5

    visit restaurant_menu_path(restaurant_slug: osteria.slug)
    assert_selector "#cart-bar", wait: 5
    within "#cart-bar" do
      assert_recased_text I18n.t("menu.cart_bar.item_count", count: 1)
    end
  end

  test "a diner can order without ever scanning a table, via /menu/:id" do
    restaurant = restaurants(:osteria)
    barolo = wines(:barolo)

    visit restaurant_menu_path(restaurant_slug: restaurant.slug)
    add_to_cart(barolo, 75)
    assert_current_path published_menu_path(restaurant), wait: 5

    go_to_cart
    assert_current_path cart_path(restaurant_slug: restaurant.slug), wait: 5

    click_button I18n.t("orders.form.submit")

    assert_text I18n.t("orders.status.statuses.pending"), wait: 5
    assert_text I18n.t("orders.status.no_table")
  end

  test "an order a guest places is visible and approvable by the restaurant's owner" do
    restaurant = restaurants(:osteria)
    barolo = wines(:barolo)
    owner = users(:owner)

    visit restaurant_menu_path(restaurant_slug: restaurant.slug)
    add_to_cart(barolo, 100)
    assert_current_path published_menu_path(restaurant), wait: 5

    go_to_cart
    assert_current_path cart_path(restaurant_slug: restaurant.slug), wait: 5

    fill_in I18n.t("orders.form.guest_name"), with: "System Test Diner"
    click_button I18n.t("orders.form.submit")
    assert_text I18n.t("orders.status.statuses.pending"), wait: 5

    sign_in_as_owner(owner)
    visit owner_restaurant_orders_path(restaurant_id: restaurant.id)
    assert_text "System Test Diner", wait: 5

    # The owner's order board is a ledger table — one <tr> per order (see
    # owner/orders/index).
    within(find("tr", text: "System Test Diner")) do
      click_button I18n.t("owner.orders.approve")
    end

    assert_text I18n.t("owner.orders.approved"), wait: 5
    within(find("tr", text: "System Test Diner")) do
      assert_recased_text I18n.t("owner.orders.statuses.approved")
    end
  end

  # --- recovering from a dropped line (final review finding 1) ---

  test "a diner can remove a dropped line and place the rest of the order" do
    restaurant = restaurants(:osteria)
    barolo = wines(:barolo)
    gavi = wines(:gavi)

    visit restaurant_menu_path(restaurant_slug: restaurant.slug)
    add_to_cart(barolo, 125)
    add_to_cart(gavi, 100)
    go_to_cart
    assert_current_path cart_path(restaurant_slug: restaurant.slug), wait: 5

    barolo.update!(active: false)
    visit cart_path(restaurant_slug: restaurant.slug)
    assert_text I18n.t("cart.dropped_items_notice"), wait: 5
    assert_text barolo.name

    remove_from_cart(I18n.t("cart.remove_item", wine: barolo.name))

    assert_no_text I18n.t("cart.dropped_items_notice"), wait: 5
    assert_no_text barolo.name
    assert_text gavi.name

    click_button I18n.t("orders.form.submit")
    assert_text I18n.t("orders.status.statuses.pending"), wait: 5
    assert_text gavi.name
  end

  # --- Bottle serving (Task 3) ---

  test "a diner adds a bottle to the cart from the menu and sees it in the cart and on the placed order" do
    restaurant = restaurants(:osteria)
    barolo = wines(:barolo)
    bottle_label = I18n.t("shared.serving.bottle", size: barolo.bottle_size_ml)

    visit restaurant_menu_path(restaurant_slug: restaurant.slug)
    add_bottle_to_cart(barolo)
    assert_current_path published_menu_path(restaurant), wait: 5

    go_to_cart
    assert_current_path cart_path(restaurant_slug: restaurant.slug), wait: 5
    assert_recased_text bottle_label, wait: 5
    assert_text format_price(barolo.price_bottle_cents)

    click_button I18n.t("orders.form.submit")

    assert_text I18n.t("orders.status.statuses.pending"), wait: 5
    assert_text barolo.name
    assert_recased_text bottle_label
    assert_text format_price(barolo.price_bottle_cents)
  end
end
