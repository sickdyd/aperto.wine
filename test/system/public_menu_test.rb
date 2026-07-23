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
