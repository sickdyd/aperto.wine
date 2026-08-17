require "test_helper"

class MenusHelperTest < ActionView::TestCase
  # menu_price_band_facet formats its boundary amounts through
  # ApplicationHelper#format_cents. Real views get it for free (Rails merges
  # every app/helpers module into one for rendering); ActionView::TestCase
  # only auto-includes the helper matching this test's own name.
  include ApplicationHelper
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
    wines(:trattoria_franciacorta).update!(active: false)

    assert_empty renderable_wine_lists([ wine_lists(:trattoria_list) ])
  end

  test "renderable_wine_lists groups a list's items by colour in enum order" do
    rendered = renderable_wine_lists([ wine_lists(:trattoria_list) ])

    _list, colour_groups = rendered.first
    # red (chianti, reserve barbaresco) before white (trattoria_white) before
    # sparkling (trattoria_franciacorta), matching Wine's color enum order
    # rather than insertion order — the franciacorta item sits at position 4,
    # after the white one, so insertion order would agree here, but the list's
    # colours sort alphabetically as [red, sparkling, white], which does not.
    assert_equal [ "red", "white", "sparkling" ], colour_groups.map(&:first)

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

    list_id = wine_lists(:trattoria_list).id
    assert_equal(
      [ "list-#{list_id}-red", "list-#{list_id}-white", "list-#{list_id}-sparkling" ],
      sections.map(&:first)
    )
    assert_equal(
      [ I18n.t("owner.wines.colors.red"), I18n.t("owner.wines.colors.white"),
        I18n.t("owner.wines.colors.sparkling") ],
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

  # --- menu_filter_facets ---

  FacetItem = Struct.new(:wine)

  # Wraps plain wines into the [list, colour_groups] shape
  # renderable_wine_lists produces, without touching the database — every
  # wine lands in a single fake "red" group since menu_filter_facets never
  # reads colour_groups' key, only each item's #wine.
  def rendered_from(wines)
    [ [ nil, [ [ "red", wines.map { |wine| FacetItem.new(wine) } ] ] ] ]
  end

  test "menu_filter_facets is empty when nothing renders" do
    assert_equal({ groups: [], wine_values: {} }, menu_filter_facets([]))
  end

  test "color facet lists only colours present, in enum order" do
    rendered = renderable_wine_lists([ wine_lists(:osteria_list) ])
    facets = menu_filter_facets(rendered)

    color_facet = facets[:groups].find { |g| g[:name] == "color" }
    assert_equal(
      [ "red", "white", "rose", "sparkling" ],
      color_facet[:options].map { |o| o[:value] }
    )
    assert_equal I18n.t("owner.wines.colors.rose"), color_facet[:options].find { |o| o[:value] == "rose" }[:label]
  end

  test "color facet does not render when only one colour is present" do
    rendered = renderable_wine_lists([ wine_lists(:winter) ]) # gavi only, white
    facets = menu_filter_facets(rendered)

    assert_nil facets[:groups].find { |g| g[:name] == "color" }
  end

  test "serving facet renders only when both servings are offered among the wines" do
    rendered = renderable_wine_lists([ wine_lists(:osteria_list) ])
    facets = menu_filter_facets(rendered)

    serving_facet = facets[:groups].find { |g| g[:name] == "serving" }
    assert_equal %w[glass bottle], serving_facet[:options].map { |o| o[:value] }
  end

  test "serving facet does not render when every wine offers only one serving" do
    # trattoria_list's wines are all glass-only — none has a bottle price.
    rendered = renderable_wine_lists([ wine_lists(:trattoria_list) ])
    facets = menu_filter_facets(rendered)

    assert_nil facets[:groups].find { |g| g[:name] == "serving" }
  end

  test "certification facet lists only certifications present among the wines" do
    # full_character_wine is the only wine with any certification set
    # (organic and natural_wine true, vegan and biodynamic false).
    rendered = renderable_wine_lists([ wine_lists(:osteria_list) ])
    facets = menu_filter_facets(rendered)

    certification_facet = facets[:groups].find { |g| g[:name] == "certification" }
    assert_equal %w[organic natural_wine], certification_facet[:options].map { |o| o[:value] }
  end

  test "certification facet does not render when fewer than two certifications are present" do
    rendered = renderable_wine_lists([ wine_lists(:trattoria_list) ]) # none certified
    facets = menu_filter_facets(rendered)

    assert_nil facets[:groups].find { |g| g[:name] == "certification" }
  end

  test "price band facet splits the rendered wines' lowest offered price into three bands" do
    # osteria_list's priced wines and their lowest offered price: barolo
    # 1500 (its cheapest glass pour undercuts its own bottle price), gavi
    # 900, full_character_wine 900 (its glass pour undercuts its bottle
    # price), bottle_only_wine 18000 (bottle only). sold_out_wine has
    # neither a glass nor a bottle price and is excluded entirely.
    rendered = renderable_wine_lists([ wine_lists(:osteria_list) ])
    facets = menu_filter_facets(rendered)

    price_band_facet = facets[:groups].find { |g| g[:name] == "price-band" }
    assert_equal %w[low mid high], price_band_facet[:options].map { |o| o[:value] }
    assert_equal "Up to €9.00", price_band_facet[:options].find { |o| o[:value] == "low" }[:label]
    assert_equal "€9.00–€15.00", price_band_facet[:options].find { |o| o[:value] == "mid" }[:label]
    assert_equal "Over €15.00", price_band_facet[:options].find { |o| o[:value] == "high" }[:label]

    assert_equal "low", facets[:wine_values][wines(:gavi)]["price-band"]
    assert_equal "mid", facets[:wine_values][wines(:barolo)]["price-band"]
    assert_equal "high", facets[:wine_values][wines(:bottle_only_wine)]["price-band"]
    # sold_out_wine has neither a glass nor a bottle price, so it takes no
    # value on this facet at all — not even a nil entry.
    assert_nil facets[:wine_values][wines(:sold_out_wine)]["price-band"]
  end

  test "price band facet does not render with fewer than three distinctly-priced wines" do
    # summer holds barolo (priced) and sold_out_wine (unpriced) — one
    # distinct price.
    rendered = renderable_wine_lists([ wine_lists(:summer) ])
    facets = menu_filter_facets(rendered)

    assert_nil facets[:groups].find { |g| g[:name] == "price-band" }
  end

  test "price band facet does not render when every wine costs the same" do
    same_priced_wines = 3.times.map do |n|
      Wine.new(restaurant: restaurants(:osteria), name: "Wine #{n}", color: :red,
               bottle_size_ml: 750, active: true, available_glasses: 5, price_125ml_cents: 1000)
    end

    facets = menu_filter_facets(rendered_from(same_priced_wines))

    assert_nil facets[:groups].find { |g| g[:name] == "price-band" }
  end

  test "price band facet does not render when the rank split still collapses to one band" do
    # Ordinary long-tail restaurant pricing: a couple of by-the-glass
    # bargains under a wall of similarly-priced bottles. Three distinct
    # prices (10, 20, 30) clear the earlier guard, but with five wines
    # clustered at the top price, both rank cutoffs (index 6/3=2 and
    # 2*6/3=4 into the 7-item sorted list) land on 30 — so "price <= 30"
    # swallows all seven wines into "low" and "mid"/"high" come out empty.
    skewed_wines =
      [ Wine.new(restaurant: restaurants(:osteria), name: "Cheap glass", color: :red,
                 bottle_size_ml: 750, active: true, available_glasses: 5, price_125ml_cents: 1000),
        Wine.new(restaurant: restaurants(:osteria), name: "Mid glass", color: :red,
                 bottle_size_ml: 750, active: true, available_glasses: 5, price_125ml_cents: 2000) ] +
      5.times.map do |n|
        Wine.new(restaurant: restaurants(:osteria), name: "Cluster wine #{n}", color: :red,
                 bottle_size_ml: 750, active: true, available_glasses: 5, price_125ml_cents: 3000)
      end

    facets = menu_filter_facets(rendered_from(skewed_wines))

    assert_nil facets[:groups].find { |g| g[:name] == "price-band" }
  end

  test "wine_values carries an entry per facet a wine actually takes a value on" do
    rendered = renderable_wine_lists([ wine_lists(:osteria_list) ])
    facets = menu_filter_facets(rendered)

    barolo_values = facets[:wine_values][wines(:barolo)]
    assert_equal "red", barolo_values["color"]
    assert_equal "glass bottle", barolo_values["serving"]
    assert_nil barolo_values["certification"]
    assert_equal "mid", barolo_values["price-band"]

    # sold_out_wine has a colour but offers neither serving, holds no
    # certification and has no price at all — only "color" survives.
    assert_equal({ "color" => "red" }, facets[:wine_values][wines(:sold_out_wine)])
  end
end
