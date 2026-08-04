require "application_system_test_case"

class WineOrderingTest < ApplicationSystemTestCase
  # Clicks the add-to-cart control for one wine at one glass size. The
  # control's visible text is aria-hidden (see menus/_wine_row) — its
  # accessible name is the wine + size aria-label alone — so this locates
  # by that aria-label rather than by visible text.
  def add_to_cart(wine, size)
    find("button[aria-label='#{I18n.t("menu.add_to_cart", wine: wine.name, size: size)}']").click
  end

  def format_price(cents)
    ApplicationController.helpers.format_cents(cents)
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

    # Adding always lands on the cart page (CartsController#add_item's
    # redirect, unchanged from Task 3) — return to the menu between adds so
    # both wines end up in the same cart before checking the sticky bar.
    add_to_cart(barolo, 125) # a non-default glass size
    assert_current_path cart_path(restaurant_id: restaurant), wait: 5
    click_link I18n.t("cart.back_to_menu")

    add_to_cart(gavi, 100)
    assert_current_path cart_path(restaurant_id: restaurant), wait: 5
    click_link I18n.t("cart.back_to_menu")

    assert_selector "#cart-bar", wait: 5
    within "#cart-bar" do
      assert_text I18n.t("menu.cart_bar.item_count", count: 2)
      assert_text format_price(barolo.price_for_glass(125) + gavi.price_for_glass(100))
      click_link I18n.t("menu.cart_bar.view_cart")
    end

    assert_current_path cart_path(restaurant_id: restaurant), wait: 5

    # Bump barolo from 1 to 2 glasses.
    within(find("div.p-4", text: barolo.name)) do
      select "2", from: "cart_item_#{barolo.id}_125_quantity"
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

    visit menu_path(id: osteria)
    add_to_cart(barolo, 125)
    assert_current_path cart_path(restaurant_id: osteria), wait: 5
    click_link I18n.t("cart.back_to_menu")
    assert_selector "#cart-bar", wait: 5

    visit menu_path(id: trattoria)
    assert_no_selector "#cart-bar", wait: 5
    visit cart_path(restaurant_id: trattoria)
    assert_text I18n.t("cart.empty"), wait: 5

    visit menu_path(id: osteria)
    assert_selector "#cart-bar", wait: 5
    within "#cart-bar" do
      assert_text I18n.t("menu.cart_bar.item_count", count: 1)
    end
  end

  test "a diner can order without ever scanning a table, via /menu/:id" do
    restaurant = restaurants(:osteria)
    barolo = wines(:barolo)

    visit menu_path(id: restaurant)
    add_to_cart(barolo, 75)
    assert_current_path cart_path(restaurant_id: restaurant), wait: 5

    click_button I18n.t("orders.form.submit")

    assert_text I18n.t("orders.status.statuses.pending"), wait: 5
    assert_text I18n.t("orders.status.no_table")
  end

  test "an order a guest places is visible and approvable by the restaurant's owner" do
    restaurant = restaurants(:osteria)
    barolo = wines(:barolo)
    owner = users(:owner)

    visit menu_path(id: restaurant)
    add_to_cart(barolo, 100)
    assert_current_path cart_path(restaurant_id: restaurant), wait: 5

    fill_in I18n.t("orders.form.guest_name"), with: "System Test Diner"
    click_button I18n.t("orders.form.submit")
    assert_text I18n.t("orders.status.statuses.pending"), wait: 5

    sign_in_as_owner(owner)
    visit owner_restaurant_orders_path(restaurant_id: restaurant.id)
    assert_text "System Test Diner", wait: 5

    within(find("div.p-4", text: "System Test Diner")) do
      click_button I18n.t("owner.orders.approve")
    end

    assert_text I18n.t("owner.orders.approved"), wait: 5
    within(find("div.p-4", text: "System Test Diner")) do
      assert_text I18n.t("owner.orders.statuses.approved")
    end
  end
end
