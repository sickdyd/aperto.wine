require "application_system_test_case"

class OwnerNavigationTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "My Restaurants", wait: 5
  end

  # ── Sidebar structure ─────────────────────────────────────────────────────

  test "owner index shows sidebar with restaurants link and no section nav" do
    sign_in_as_owner

    within ".drawer-side" do
      assert_link "aperto.wine"
      assert_link "My Restaurants"
      assert_no_link "Orders"
      assert_text users(:owner).name
      assert_button "Sign Out"
    end
  end

  test "restaurant pages show section navigation in sidebar" do
    sign_in_as_owner
    visit owner_restaurant_path(id: restaurants(:osteria).id)

    within ".drawer-side" do
      assert_link "Overview"
      assert_link "My Wines"
      assert_link "Wine Lists"
      assert_link "Orders"
      assert_link "QR Code"
      assert_link "Settings"
    end
  end

  test "My Wines and Wine Lists are separate sections with independent highlighting" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)
    visit owner_restaurant_path(id: restaurant.id)

    within ".drawer-side" do
      click_link "My Wines"
    end
    assert_current_path owner_restaurant_wines_path(restaurant_id: restaurant.id)
    assert_selector ".drawer-side a.menu-active", text: "My Wines"
    assert_no_selector ".drawer-side a.menu-active", text: "Wine Lists"

    within ".drawer-side" do
      click_link "Wine Lists"
    end
    assert_current_path owner_restaurant_wine_lists_path(restaurant_id: restaurant.id)
    assert_selector ".drawer-side a.menu-active", text: "Wine Lists"
    assert_no_selector ".drawer-side a.menu-active", text: "My Wines"
  end

  # ── Section navigation ────────────────────────────────────────────────────

  test "sidebar links navigate between restaurant sections" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)
    visit owner_restaurant_path(id: restaurant.id)

    within ".drawer-side" do
      click_link "Orders"
    end
    assert_current_path owner_restaurant_orders_path(restaurant_id: restaurant.id)
    assert_selector ".drawer-side a.menu-active", text: "Orders"

    within ".drawer-side" do
      click_link "Wine Lists"
    end
    assert_current_path owner_restaurant_wine_lists_path(restaurant_id: restaurant.id)
    assert_selector ".drawer-side a.menu-active", text: "Wine Lists"

    within ".drawer-side" do
      click_link "Settings"
    end
    assert_current_path edit_owner_restaurant_path(id: restaurant.id)
    assert_selector ".drawer-side a.menu-active", text: "Settings"
  end

  test "active section is highlighted" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)
    visit owner_restaurant_orders_path(restaurant_id: restaurant.id)

    within ".drawer-side" do
      assert_selector "a.menu-active", text: "Orders"
    end
  end

  test "owner with no restaurants sees no switcher and only the restaurants link" do
    user = users(:owner_no_restaurants)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "No restaurants yet", wait: 5

    within ".drawer-side" do
      assert_no_selector "summary"
      assert_link "My Restaurants"
      assert_no_link "Orders"
    end
  end

  # ── Restaurant switcher ───────────────────────────────────────────────────

  test "restaurant switcher lists restaurants and switches context" do
    sign_in_as_owner
    visit owner_restaurant_path(id: restaurants(:osteria).id)

    within ".drawer-side" do
      find("summary", text: "Osteria del Borgo").click
      click_link "Closed Place"
    end

    assert_current_path owner_restaurant_path(id: restaurants(:inactive_restaurant).id)
    within ".drawer-side" do
      assert_selector "summary", text: "Closed Place"
    end
  end

  test "restaurant switcher offers all restaurants and new restaurant actions" do
    sign_in_as_owner
    visit owner_restaurant_path(id: restaurants(:osteria).id)

    within ".drawer-side" do
      find("summary", text: "Osteria del Borgo").click
      click_link "New restaurant"
    end

    assert_current_path new_owner_restaurant_path
  end

  # ── Mobile drawer ─────────────────────────────────────────────────────────

  test "on small screens the sidebar is hidden behind a hamburger toggle" do
    sign_in_as_owner
    page.driver.browser.manage.window.resize_to(390, 844)
    visit owner_restaurant_path(id: restaurants(:osteria).id)

    assert_no_selector ".drawer-side a", text: "Overview", visible: :visible

    find("label[for='owner-drawer']", match: :first).click

    within ".drawer-side" do
      assert_link "Overview", wait: 5
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 900)
  end
end
