require "application_system_test_case"

class MenuFiltersTest < ApplicationSystemTestCase
  def visit_menu
    restaurant = restaurants(:osteria)
    visit restaurant_menu_path(restaurant_slug: restaurant.slug)
    assert_text "Barolo Riserva", wait: 5
  end

  def color_chip(colour)
    I18n.t("owner.wines.colors.#{colour}")
  end

  def certification_chip(cert)
    I18n.t("shared.certifications.#{cert}")
  end

  def serving_chip(serving)
    I18n.t("menu.filters.serving.#{serving}")
  end

  def clear_all_button
    I18n.t("menu.filters.clear_all")
  end

  # osteria's published list renders five wines: Barolo Riserva (red, by the
  # glass and the bottle, organic/natural_wine unset), Gavi di Gavi (white,
  # glass only), Sold Out Wine (red, neither serving offered), Amphora
  # Rosato (rose, both servings, organic and natural_wine), and Cellar
  # Reserve Magnum (sparkling, bottle only).

  test "tapping a colour chip hides other colours" do
    visit_menu

    assert_text "Gavi di Gavi"
    assert_text "Amphora Rosato"

    click_button color_chip("red")

    assert_text "Barolo Riserva", wait: 5
    assert_text "Sold Out Wine"
    assert_no_text "Gavi di Gavi"
    assert_no_text "Amphora Rosato"
    assert_no_text "Cellar Reserve Magnum"
  end

  test "two chips in the same facet OR together" do
    visit_menu

    click_button color_chip("red")
    click_button color_chip("white")

    assert_text "Barolo Riserva", wait: 5
    assert_text "Sold Out Wine"
    assert_text "Gavi di Gavi"
    assert_no_text "Amphora Rosato"
    assert_no_text "Cellar Reserve Magnum"
  end

  test "chips in different facets AND together" do
    visit_menu

    click_button color_chip("red")
    click_button serving_chip("bottle")

    # Sold Out Wine is red but offers neither serving, so the bottle facet
    # drops it even though the colour facet alone would have kept it.
    assert_text "Barolo Riserva", wait: 5
    assert_no_text "Sold Out Wine"
    assert_no_text "Gavi di Gavi"
    assert_no_text "Amphora Rosato"
    assert_no_text "Cellar Reserve Magnum"
  end

  test "a chip and a search term compose" do
    visit_menu

    click_button color_chip("white")
    fill_in I18n.t("menu.search_placeholder"), with: "Barolo"

    # Gavi di Gavi is the only white wine, and its name doesn't match
    # "Barolo" — the text search and the colour chip both have to pass.
    assert_text I18n.t("menu.no_results"), wait: 5
    assert_no_text "Barolo Riserva"
    assert_no_text "Gavi di Gavi"
  end

  test "clear all restores the text search and every chip" do
    visit_menu

    assert_no_button clear_all_button

    click_button color_chip("red")
    fill_in I18n.t("menu.search_placeholder"), with: "xyz"
    assert_text I18n.t("menu.no_results"), wait: 5

    click_button clear_all_button

    assert_text "Barolo Riserva", wait: 5
    assert_text "Gavi di Gavi"
    assert_text "Amphora Rosato"
    assert_text "Cellar Reserve Magnum"
    assert_no_button clear_all_button
    # ".chip" renders text upper-cased via CSS, hence the case-insensitive
    # match — see MenuSearchTest#assert_colour_section for the same trap.
    assert_selector "button[aria-pressed='false']", text: /\A#{Regexp.escape(color_chip("red"))}\z/i
  end

  test "shows the empty state when a chip combination matches nothing" do
    visit_menu

    # Gavi di Gavi is white but offers no bottle — no wine is both.
    click_button color_chip("white")
    click_button serving_chip("bottle")

    assert_text I18n.t("menu.no_results"), wait: 5
    assert_no_text "Gavi di Gavi"
  end

  test "a certification chip filters to wines carrying that certification" do
    visit_menu

    click_button certification_chip("organic")

    assert_text "Amphora Rosato", wait: 5
    assert_no_text "Barolo Riserva"
    assert_no_text "Gavi di Gavi"
    assert_no_text "Cellar Reserve Magnum"
  end
end
