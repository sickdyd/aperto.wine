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

  def filters_toggle
    I18n.t("menu.filters.toggle")
  end

  # The facet chips live inside a disclosure panel that starts collapsed, so
  # the wine list — not the filter chrome — is what a diner sees first. Every
  # test that reaches for a chip has to open it, exactly as a diner does.
  def open_filters
    find("button[aria-controls='menu-filter-panel']").click
    assert_selector "#menu-filter-panel", visible: true, wait: 5
  end

  # osteria's published list renders five wines: Barolo Riserva (red, by the
  # glass and the bottle, organic/natural_wine unset), Gavi di Gavi (white,
  # glass only), Sold Out Wine (red, neither serving offered), Amphora
  # Rosato (rose, both servings, organic and natural_wine), and Cellar
  # Reserve Magnum (sparkling, bottle only).

  test "tapping a colour chip hides other colours" do
    visit_menu

    open_filters

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

    open_filters

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

    open_filters

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

    open_filters

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

    open_filters

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

    open_filters

    # Gavi di Gavi is white but offers no bottle — no wine is both.
    click_button color_chip("white")
    click_button serving_chip("bottle")

    assert_text I18n.t("menu.no_results"), wait: 5
    assert_no_text "Gavi di Gavi"
  end

  test "a certification chip filters to wines carrying that certification" do
    visit_menu

    open_filters

    click_button certification_chip("organic")

    assert_text "Amphora Rosato", wait: 5
    assert_no_text "Barolo Riserva"
    assert_no_text "Gavi di Gavi"
    assert_no_text "Cellar Reserve Magnum"
  end

  # --- The filter disclosure ---

  test "the facet chips start collapsed behind the filters trigger" do
    visit_menu

    trigger = find("button[aria-controls='menu-filter-panel']")
    assert_equal "false", trigger[:"aria-expanded"]
    # ".chip" upper-cases its text in CSS, so Selenium reports the trigger's
    # label upper-cased — hence the case-insensitive match.
    assert_text(/#{Regexp.escape(filters_toggle)}/i)
    assert_no_selector "#menu-filter-panel", visible: true
    assert_no_button color_chip("red")

    trigger.click

    assert_selector "#menu-filter-panel", visible: true, wait: 5
    assert_equal "true", find("button[aria-controls='menu-filter-panel']")[:"aria-expanded"]
    assert_button color_chip("red")
  end

  test "the filters trigger collapses again on a second press" do
    visit_menu

    open_filters
    find("button[aria-controls='menu-filter-panel']").click

    assert_no_selector "#menu-filter-panel", visible: true, wait: 5
    assert_equal "false", find("button[aria-controls='menu-filter-panel']")[:"aria-expanded"]
  end

  # The count is the only thing carrying applied-filter state once the panel is
  # collapsed again, so a diner is never filtering blind.
  test "the filters trigger counts the applied facets and keeps them across a collapse" do
    visit_menu

    assert_no_selector "[data-list-filter-target='count']", visible: true

    open_filters
    click_button color_chip("red")
    assert_selector "[data-list-filter-target='count']", text: "1", wait: 5

    click_button color_chip("white")
    assert_selector "[data-list-filter-target='count']", text: "2"

    # Collapsing must not silently drop the filters it is hiding.
    find("button[aria-controls='menu-filter-panel']").click
    assert_no_selector "#menu-filter-panel", visible: true, wait: 5
    assert_selector "[data-list-filter-target='count']", text: "2"
    assert_no_text "Amphora Rosato"

    open_filters
    click_button clear_all_button

    assert_no_selector "[data-list-filter-target='count']", visible: true
    assert_text "Amphora Rosato", wait: 5
  end

  # The badge is a bare numeral and is hidden from assistive technology; the
  # tally in words is what a screen reader actually gets. It is assembled by
  # substituting into a translation that reaches the controller through a data
  # attribute, so the Ruby-side interpolation key and the JavaScript-side
  # search string have to keep matching — rename one without the other and the
  # visible badge would still be right while the spoken label silently
  # degraded to a literal "%{count}". Nothing else in the suite would notice.
  test "the applied tally is spelled out for assistive technology" do
    visit_menu

    open_filters
    click_button color_chip("red")

    label = find("[data-list-filter-target='countLabel']", visible: :all)
    expected = I18n.t("menu.filters.applied_count", count: 1)
    assert_equal expected, label.text(:all).strip
    refute_includes label.text(:all), "%{count}",
      "the placeholder was never substituted — the Ruby interpolation key and " \
      "the string list_filter_controller.js replaces have drifted apart"

    # The trigger's own label sits beside it inside the same button, so the
    # composed accessible name must read as one phrase rather than saying
    # "Filters" twice.
    refute_includes label.text(:all).downcase, filters_toggle.downcase,
      "the sr-only tally is a suffix to the trigger's visible label; repeating " \
      "the word here has it announced twice"
  end

  # Regression: the colour facet chips and the section jump links carry the
  # same words ("Red", "White", …) in the same chip shape. Rendered one under
  # the other they read as one row printed twice — the defect this disclosure
  # fixes. Collapsed, exactly one set of colour words is on the page, and the
  # two are never the same kind of control: the facets are toggle buttons, the
  # jump targets are links.
  test "colour words appear once while the filter panel is collapsed" do
    visit_menu

    assert_link color_chip("red")
    assert_no_button color_chip("red")

    open_filters

    assert_button color_chip("red")
    assert_link color_chip("red")
    assert_selector "button[aria-pressed][data-facet-name='color']", count: 4
  end
end
