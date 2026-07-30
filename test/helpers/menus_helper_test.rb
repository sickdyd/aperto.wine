require "test_helper"

class MenusHelperTest < ActionView::TestCase
  test "renderable_wine_lists keeps only lists with active wines and sorts items" do
    rendered = renderable_wine_lists([ wine_lists(:summer), wine_lists(:winter) ])

    assert_equal [ wine_lists(:summer), wine_lists(:winter) ], rendered.map(&:first)

    summer_colour_groups = rendered.first.last
    assert_equal [ "red" ], summer_colour_groups.map(&:first)
    assert_equal [ wines(:barolo), wines(:sold_out_wine) ], summer_colour_groups.first.last.map(&:wine)
  end

  test "renderable_wine_lists drops a list whose wines are all inactive" do
    wines(:chianti).update!(active: false)
    wines(:trattoria_sold_out).update!(active: false)
    wines(:trattoria_white).update!(active: false)

    assert_empty renderable_wine_lists([ wine_lists(:trattoria_list) ])
  end

  test "renderable_wine_lists groups a list's items by colour in enum order" do
    rendered = renderable_wine_lists([ wine_lists(:trattoria_list) ])

    _list, colour_groups = rendered.first
    # red (chianti, reserve barbaresco) before white (trattoria_white),
    # matching Wine's color enum order, not insertion order.
    assert_equal [ "red", "white" ], colour_groups.map(&:first)

    red_wines = colour_groups.first.last.map(&:wine)
    assert_equal [ wines(:chianti), wines(:trattoria_sold_out) ], red_wines
  end

  test "renderable_wine_lists omits colours with no active items" do
    rendered = renderable_wine_lists([ wine_lists(:winter) ])

    _list, colour_groups = rendered.first
    assert_equal [ "white" ], colour_groups.map(&:first)
  end

  test "renderable_wine_lists orders colours by enum, not alphabetically or by item position" do
    # mixed_order_list's item positions are white(1), dessert(2), red(3) — the
    # exact reverse of a naive "position order" implementation, and its
    # colour set (dessert, red, white) sorts alphabetically as
    # ["dessert", "red", "white"], which diverges from Wine's declared enum
    # order (red: 0, white: 1, dessert: 4). Only an enum-order-based
    # implementation produces ["red", "white", "dessert"] here.
    rendered = renderable_wine_lists([ wine_lists(:mixed_order_list) ])

    _list, colour_groups = rendered.first
    assert_equal [ "red", "white", "dessert" ], colour_groups.map(&:first)
  end

  test "menu_nav_sections uses the plain colour name when only one list renders" do
    rendered = renderable_wine_lists([ wine_lists(:trattoria_list) ])

    sections = menu_nav_sections(rendered)

    assert_equal(
      [ "list-#{wine_lists(:trattoria_list).id}-red", "list-#{wine_lists(:trattoria_list).id}-white" ],
      sections.map(&:first)
    )
    assert_equal(
      [ I18n.t("owner.wines.colors.red"), I18n.t("owner.wines.colors.white") ],
      sections.map(&:last)
    )
  end

  test "menu_nav_sections qualifies the label with the list name when several lists render" do
    rendered = renderable_wine_lists([ wine_lists(:summer), wine_lists(:winter) ])

    sections = menu_nav_sections(rendered)

    assert_equal(
      [ "list-#{wine_lists(:summer).id}-red", "list-#{wine_lists(:winter).id}-white" ],
      sections.map(&:first)
    )
    assert_equal(
      [ "Summer Selection · #{I18n.t('owner.wines.colors.red')}", "Winter Selection · #{I18n.t('owner.wines.colors.white')}" ],
      sections.map(&:last)
    )
  end

  test "menu_nav_sections is empty when nothing renders" do
    assert_empty menu_nav_sections([])
  end
end
