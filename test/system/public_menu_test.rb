require "application_system_test_case"

class PublicMenuTest < ApplicationSystemTestCase
  test "visitor can view public menu for a restaurant" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    assert_selector "h1", text: restaurant.name
    assert_text restaurant.address
  end

  test "menu shows available wines" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    assert_text "Barolo Riserva"
    assert_text "Gavi di Gavi"
  end

  test "menu displays wine producer and grape variety details" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    assert_text "Giacomo Conterno"
    assert_text "Nebbiolo"
    assert_text "La Scolca"
    assert_text "Cortese"
  end

  test "menu shows glass size labels for available wines" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    # barolo has price_75ml_cents: 1500
    assert_text "75ml"
  end

  test "sold out wine shows sold out badge" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    assert_text I18n.t("shared.sold_out")
  end

  test "menu marks each wine with a color dot" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    # barolo is a red wine
    assert_selector ".wine-dot.wine-dot-red"
    # gavi is a white wine
    assert_selector ".wine-dot.wine-dot-white"
  end

  test "menu has a search field" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    assert_selector "input[type='search']"
  end

  test "menu shows powered by aperto.wine footer" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    assert_text I18n.t("menu.powered_by")
    assert_link "aperto.wine"
  end

  test "menu is accessible without authentication" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    assert_selector "h1", text: restaurant.name
  end

  test "aperto.wine link in menu footer points to root" do
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)

    click_link "aperto.wine"
    assert_current_path root_path
  end

  # --- Section navigation ---

  def section_nav_selector
    "nav[aria-label='#{I18n.t("menu.sections_nav_label")}']"
  end

  test "menu with multiple sections shows jump navigation chips" do
    visit menu_path(id: restaurants(:trattoria).id)

    within section_nav_selector do
      assert_link "House Picks"
      assert_link I18n.t("owner.wines.colors.red")
    end

    assert_selector "section#list-#{wine_lists(:trattoria_list).id}"
    assert_selector "section#color-red"
  end

  test "clicking a jump chip navigates to that section anchor" do
    visit menu_path(id: restaurants(:trattoria).id)

    within section_nav_selector do
      click_link I18n.t("owner.wines.colors.red")
    end

    assert page.has_current_path?(/#color-red\z/, url: true),
           "expected URL to gain the #color-red fragment, got #{current_url}"
  end

  test "menu with a single section shows no jump navigation" do
    restaurants(:trattoria).update!(all_wines_list_active: false)
    visit menu_path(id: restaurants(:trattoria).id)

    assert_text "House Picks"
    assert_no_selector section_nav_selector
  end

  # --- Curated lists ---

  test "restaurant with an active list shows its curated list" do
    visit menu_path(id: restaurants(:trattoria).id)

    assert_text "House Picks"
    assert_text "Chianti Classico"
  end

  test "a featured but sold-out wine appears as currently unavailable" do
    visit menu_path(id: restaurants(:trattoria).id)

    assert_text "Reserve Barbaresco"
    assert_text I18n.t("menu.unavailable")
  end
end
