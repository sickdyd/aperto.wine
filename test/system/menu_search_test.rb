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

  test "shows a no-results message when nothing matches" do
    visit_menu

    fill_in I18n.t("menu.search_placeholder"), with: "nonexistent wine xyz"

    assert_text I18n.t("menu.no_results"), wait: 5
    assert_no_text "Barolo Riserva"
    assert_no_text "Gavi di Gavi"
  end

  test "a color section hides entirely once all its wines are filtered out" do
    visit_menu

    assert_text I18n.t("owner.wines.colors.red"), wait: 5
    assert_text I18n.t("owner.wines.colors.white"), wait: 5

    fill_in I18n.t("menu.search_placeholder"), with: "Barolo"

    # Gavi di Gavi is the only white wine on this menu, so the whole "White"
    # section (heading included) disappears once it is filtered out.
    assert_text I18n.t("owner.wines.colors.red"), wait: 5
    assert_no_text I18n.t("owner.wines.colors.white")
  end
end
