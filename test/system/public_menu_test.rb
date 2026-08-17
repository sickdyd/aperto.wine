require "application_system_test_case"

class PublicMenuTest < ApplicationSystemTestCase
  # The ledger sets the sheet's running text — address, tags, foot, colour
  # headings — as mono small caps, so Selenium reports it upper-cased. These
  # assertions match case-insensitively rather than hard-coding the transform.
  test "visitor can view public menu for a restaurant" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    assert_selector "h1", text: restaurant.name
    assert_selector ".sheet-address", text: /#{Regexp.escape(restaurant.address)}/i
  end

  test "menu shows available wines" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    assert_text "Barolo Riserva"
    assert_text "Gavi di Gavi"
  end

  test "menu displays wine producer and grape variety details" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    assert_text "Giacomo Conterno"
    assert_text "Nebbiolo"
    assert_text "La Scolca"
    assert_text "Cortese"
  end

  test "menu shows glass size labels for available wines" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    # barolo has price_75ml_cents: 1500
    assert_selector ".price-size", text: /75\s*ml/i
  end

  test "sold out wine shows unavailable tag" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    assert_selector ".tag-out", text: /#{Regexp.escape(I18n.t("menu.unavailable"))}/i
  end

  test "menu marks each wine with a color dot" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    # barolo is a red wine
    assert_selector ".wine-dot.wine-dot-red"
    # gavi is a white wine
    assert_selector ".wine-dot.wine-dot-white"
  end

  test "menu has a search field" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    assert_selector "input[type='search']"
  end

  test "menu shows powered by aperto.wine footer" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    assert_selector ".sheet-foot", text: /#{Regexp.escape(I18n.t("menu.powered_by"))}/i
    assert_link "aperto.wine"
  end

  test "menu is accessible without authentication" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    assert_selector "h1", text: restaurant.name
  end

  test "aperto.wine link in menu footer points to root" do
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)

    click_link "aperto.wine"
    assert_current_path root_path
  end

  # --- Section navigation ---

  def section_nav_selector
    "nav[aria-label='#{I18n.t("menu.sections_nav_label")}']"
  end

  test "menu with multiple sections shows jump navigation chips" do
    # trattoria_list ("House Picks") holds both red and white wines, so it
    # renders two colour sections — enough for jump-nav chips to appear.
    list = wine_lists(:trattoria_list)
    visit restaurant_menu_path(restaurant_slug: restaurants(:trattoria).slug)

    within section_nav_selector do
      assert_link I18n.t("owner.wines.colors.red")
      assert_link I18n.t("owner.wines.colors.white")
    end

    assert_selector "section#list-#{list.id}-red"
    assert_selector "section#list-#{list.id}-white"
  end

  test "clicking a jump chip navigates to that section anchor" do
    list = wine_lists(:trattoria_list)
    visit restaurant_menu_path(restaurant_slug: restaurants(:trattoria).slug)

    within section_nav_selector do
      click_link I18n.t("owner.wines.colors.red")
    end

    assert page.has_current_path?(/#list-#{list.id}-red\z/, url: true),
           "expected URL to gain the #list-#{list.id}-red fragment, got #{current_url}"
  end

  test "menu with a single section shows no jump navigation" do
    # A published list holding wines of a single colour renders one section —
    # too few for jump-nav chips to appear.
    wine_lists(:summer).publish! # summer holds only red wines
    visit restaurant_menu_path(restaurant_slug: restaurants(:osteria).slug)

    assert_text "Summer Selection"
    assert_no_selector section_nav_selector
  end

  # --- Curated lists ---

  test "restaurant with an active list shows its curated list" do
    visit restaurant_menu_path(restaurant_slug: restaurants(:trattoria).slug)

    assert_text "House Picks"
    assert_text "Chianti Classico"
  end

  test "a featured but sold-out wine appears as currently unavailable" do
    visit restaurant_menu_path(restaurant_slug: restaurants(:trattoria).slug)

    assert_text "Reserve Barbaresco"
    assert_selector ".tag-out", text: /#{Regexp.escape(I18n.t("menu.unavailable"))}/i
  end
end
