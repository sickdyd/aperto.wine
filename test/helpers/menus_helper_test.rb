require "test_helper"

class MenusHelperTest < ActionView::TestCase
  test "renderable_wine_lists keeps only lists with active wines and sorts items" do
    rendered = renderable_wine_lists([ wine_lists(:summer), wine_lists(:winter) ])

    assert_equal [ wine_lists(:summer), wine_lists(:winter) ], rendered.map(&:first)
    assert_equal [ wines(:barolo), wines(:sold_out_wine) ], rendered.first.last.map(&:wine)
  end

  test "renderable_wine_lists drops a list whose wines are all inactive" do
    wines(:chianti).update!(active: false)
    wines(:trattoria_sold_out).update!(active: false)

    assert_empty renderable_wine_lists([ wine_lists(:trattoria_list) ])
  end

  test "menu_nav_sections lists curated lists before color groups with stable ids" do
    rendered = renderable_wine_lists([ wine_lists(:trattoria_list) ])
    color_groups = { "red" => [ wines(:chianti) ] }

    sections = menu_nav_sections(rendered, color_groups)

    assert_equal [ "list-#{wine_lists(:trattoria_list).id}", "color-red" ], sections.map(&:first)
    assert_equal [ "House Picks", I18n.t("owner.wines.colors.red") ], sections.map(&:last)
  end

  test "menu_nav_sections is empty when nothing renders" do
    assert_empty menu_nav_sections([], {})
  end
end
