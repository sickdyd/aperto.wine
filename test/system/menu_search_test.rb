require "application_system_test_case"

class MenuSearchTest < ApplicationSystemTestCase
  def visit_menu
    restaurant = restaurants(:osteria)
    visit menu_path(id: restaurant.id)
    assert_text "Barolo Riserva", wait: 5
  end

  test "typing a wine name filters the menu and clearing restores it" do
    visit_menu

    assert_text "Gavi di Gavi"

    fill_in I18n.t("menu.search_placeholder"), with: "Barolo"

    assert_text "Barolo Riserva", wait: 5
    assert_no_text "Gavi di Gavi"

    fill_in I18n.t("menu.search_placeholder"), with: ""

    assert_text "Barolo Riserva", wait: 5
    assert_text "Gavi di Gavi"
  end

  test "typing a vintage year filters the menu to wines from that year" do
    visit_menu

    assert_text "Gavi di Gavi"

    fill_in I18n.t("menu.search_placeholder"), with: "2018"

    assert_text "Barolo Riserva", wait: 5
    assert_no_text "Gavi di Gavi"
  end

  test "shows a no-results message when nothing matches" do
    visit_menu

    fill_in I18n.t("menu.search_placeholder"), with: "nonexistent wine xyz"

    assert_text I18n.t("menu.no_results"), wait: 5
    assert_no_text "Barolo Riserva"
    assert_no_text "Gavi di Gavi"
  end

  # Colour headings are scoped to ".group-title" rather than matched against the
  # whole page: the jump-nav chips name the same colours and stay put while a
  # section is filtered away. They are also mono small caps, so Selenium reports
  # them upper-cased — hence the case-insensitive match.
  def assert_colour_section(colour)
    assert_selector ".group-title", text: /#{Regexp.escape(I18n.t("owner.wines.colors.#{colour}"))}/i, wait: 5
  end

  def assert_no_colour_section(colour)
    assert_no_selector ".group-title", text: /#{Regexp.escape(I18n.t("owner.wines.colors.#{colour}"))}/i
  end

  test "a color section hides entirely once all its wines are filtered out" do
    visit_menu

    assert_colour_section "red"
    assert_colour_section "white"

    fill_in I18n.t("menu.search_placeholder"), with: "Barolo"

    # Gavi di Gavi is the only white wine on this menu, so the whole "White"
    # section (heading included) disappears once it is filtered out.
    assert_colour_section "red"
    assert_no_colour_section "white"
  end

  test "a list heading hides once every wine on that list is filtered out" do
    visit_menu

    assert_text wine_lists(:osteria_list).name, wait: 5

    fill_in I18n.t("menu.search_placeholder"), with: "nonexistent wine xyz"

    # The list name wrapper is its own filter group, so a list with no matching
    # wines must not leave a bare heading stranded above the no-results line.
    assert_text I18n.t("menu.no_results"), wait: 5
    assert_no_text wine_lists(:osteria_list).name
  end
end
