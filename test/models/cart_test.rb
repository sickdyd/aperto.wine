require "test_helper"

class CartTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
    @gavi = wines(:gavi)
    @sold_out = wines(:sold_out_wine)
    @barbera = wines(:trattoria_barbera)
    @unlisted = wines(:unlisted_wine)
    @inactive_list_only = wines(:osteria_moscato)
  end

  def cart_for(restaurant, session: {})
    Cart.new(session: session, restaurant: restaurant)
  end

  # Ad-hoc wines created mid-test need to sit on a published list to be
  # addable now that the cart enforces the same publication boundary as the
  # public menu — wine_lists(:osteria_list) is osteria's active list.
  def create_published_wine(attributes)
    wine = @osteria.wines.create!(attributes)
    wine_lists(:osteria_list).wine_list_items.create!(wine: wine, position: wine.position)
    wine
  end

  # --- add ---

  test "add stores a new line and items exposes it in insertion order" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)

    assert_equal [ @barolo, @gavi ], cart.items.map(&:wine)
    assert_equal [ 125, 100 ], cart.items.map(&:glass_size_ml)
    assert_equal [ 2, 1 ], cart.items.map(&:quantity)
  end

  test "add returns a successful result" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    assert result.success?
    assert_nil result.error
  end

  test "add rejects a wine belonging to another restaurant" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barbera.id, glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
    assert_empty cart.items
  end

  test "add rejects a wine id that does not exist" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: -1, glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
  end

  # --- publication boundary (Task 6 security fix) ---
  #
  # The public menu only shows wines reachable through an active wine list
  # (MenusController#show / WineList.active). The cart must enforce the same
  # boundary — an owner's "Published" toggle would otherwise be cosmetic:
  # the wine could still be added by id and ordered.

  test "add rejects a wine whose only list is inactive" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @inactive_list_only.id, glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
    assert_empty cart.items
  end

  test "add rejects a wine that belongs to no list at all" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @unlisted.id, glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
    assert_empty cart.items
  end

  test "a normally published wine still adds and reads back fine" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    assert result.success?
    assert_equal [ @barolo ], cart.items.map(&:wine)
  end

  test "a wine added while published is dropped on read once its list is un-published" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    wine_lists(:osteria_list).update!(active: false)

    assert_empty cart.items
    assert_equal 1, cart.dropped_items.size
    dropped = cart.dropped_items.first
    assert_equal @barolo.id, dropped.wine_id
    assert_equal :wine_not_found, dropped.reason
  end

  test "add rejects an unavailable wine" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @sold_out.id, glass_size_ml: 100, quantity: 1)

    assert_not result.success?
    assert_equal :wine_unavailable, result.error
    assert_empty cart.items
  end

  test "add rejects a glass size outside Wine::GLASS_SIZES" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @gavi.id, glass_size_ml: 60, quantity: 1)

    assert_not result.success?
    assert_equal :invalid_glass_size, result.error
    assert_empty cart.items
  end

  test "add rejects a glass size the wine has no price for" do
    cart = cart_for(@osteria)

    # gavi has no price_75ml_cents set on the fixture
    result = cart.add(wine_id: @gavi.id, glass_size_ml: 75, quantity: 1)

    assert_not result.success?
    assert_equal :price_unavailable, result.error
    assert_empty cart.items
  end

  test "add clamps quantity above the max down to MAX_QUANTITY_PER_ITEM" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 999)

    assert_equal Cart::MAX_QUANTITY_PER_ITEM, cart.items.first.quantity
  end

  test "add clamps a zero or negative quantity up to 1" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 0)

    assert_equal 1, cart.items.first.quantity
  end

  test "re-adding the same wine and glass size merges into the existing line" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 3)

    assert_equal 1, cart.items.size
    assert_equal 5, cart.items.first.quantity
  end

  test "adding a different glass size for the same wine creates a separate line" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @barolo.id, glass_size_ml: 100, quantity: 1)

    assert_equal 2, cart.items.size
  end

  test "a merged quantity is clamped to MAX_QUANTITY_PER_ITEM" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 15)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 15)

    assert_equal Cart::MAX_QUANTITY_PER_ITEM, cart.items.first.quantity
  end

  test "rejects a new distinct line once MAX_DISTINCT_ITEMS is reached, but still allows incrementing an existing line" do
    cart = cart_for(@osteria)
    wines = Array.new(Cart::MAX_DISTINCT_ITEMS) do |i|
      create_published_wine(
        name: "Filler Wine #{i}", color: :red, bottle_size_ml: 750,
        price_125ml_cents: 1000, available_glasses: 5, active: true, position: i
      )
    end
    wines.each { |wine| cart.add(wine_id: wine.id, glass_size_ml: 125, quantity: 1) }
    assert_equal Cart::MAX_DISTINCT_ITEMS, cart.items.size

    extra = create_published_wine(
      name: "One Too Many", color: :red, bottle_size_ml: 750,
      price_125ml_cents: 1000, available_glasses: 5, active: true, position: 999
    )
    result = cart.add(wine_id: extra.id, glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :cart_full, result.error
    assert_equal Cart::MAX_DISTINCT_ITEMS, cart.items.size

    increment_result = cart.add(wine_id: wines.first.id, glass_size_ml: 125, quantity: 1)

    assert increment_result.success?
    assert_equal 2, cart.items.first.quantity
  end

  # --- update_quantity ---

  test "update_quantity changes an existing line's quantity" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    result = cart.update_quantity(wine_id: @barolo.id, glass_size_ml: 125, quantity: 4)

    assert result.success?
    assert_equal 4, cart.items.first.quantity
  end

  test "update_quantity clamps the new quantity to MAX_QUANTITY_PER_ITEM" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    cart.update_quantity(wine_id: @barolo.id, glass_size_ml: 125, quantity: 999)

    assert_equal Cart::MAX_QUANTITY_PER_ITEM, cart.items.first.quantity
  end

  test "update_quantity to zero removes the line" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    result = cart.update_quantity(wine_id: @barolo.id, glass_size_ml: 125, quantity: 0)

    assert result.success?
    assert_empty cart.items
  end

  test "update_quantity to a negative number removes the line" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    cart.update_quantity(wine_id: @barolo.id, glass_size_ml: 125, quantity: -3)

    assert_empty cart.items
  end

  test "update_quantity on a line that is not in the cart fails without raising" do
    cart = cart_for(@osteria)

    result = cart.update_quantity(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
  end

  # --- remove ---

  test "remove drops the matching line" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)

    result = cart.remove(wine_id: @barolo.id, glass_size_ml: 125)

    assert result.success?
    assert_equal [ @gavi ], cart.items.map(&:wine)
  end

  test "remove on a line that is not present is a harmless no-op" do
    cart = cart_for(@osteria)

    result = cart.remove(wine_id: @barolo.id, glass_size_ml: 125)

    assert result.success?
    assert_empty cart.items
  end

  # --- totals ---

  test "total_cents and item_count sum across multiple lines" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 3)

    expected_total = (@barolo.price_for_glass(125) * 2) + (@gavi.price_for_glass(100) * 3)

    assert_equal expected_total, cart.total_cents
    assert_equal 5, cart.item_count
  end

  test "empty? reflects whether the cart has any lines" do
    cart = cart_for(@osteria)
    assert cart.empty?

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    assert_not cart.empty?
  end

  # --- clear and multi-restaurant isolation ---

  test "two restaurants' carts stay independent in one session" do
    session = {}
    osteria_cart = cart_for(@osteria, session: session)
    trattoria_cart = cart_for(@trattoria, session: session)

    osteria_cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    trattoria_cart.add(wine_id: @barbera.id, glass_size_ml: 125, quantity: 1)

    assert_equal [ @barolo ], osteria_cart.items.map(&:wine)
    assert_equal [ @barbera ], trattoria_cart.items.map(&:wine)
  end

  test "clear empties only this restaurant's cart, leaving the other restaurant's cart intact" do
    session = {}
    osteria_cart = cart_for(@osteria, session: session)
    trattoria_cart = cart_for(@trattoria, session: session)
    osteria_cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    trattoria_cart.add(wine_id: @barbera.id, glass_size_ml: 125, quantity: 1)

    osteria_cart.clear

    assert_empty osteria_cart.items
    assert_equal [ @barbera ], trattoria_cart.items.map(&:wine)
  end

  # --- stale reads / dropped_items ---

  test "a line whose wine was deleted after being added is dropped and reported" do
    session = {}
    cart = cart_for(@osteria, session: session)
    # A wine with no order_items referencing it, so it can actually be
    # destroyed (barolo/gavi are pinned by fixtures via a real FK).
    doomed_wine = create_published_wine(
      name: "Doomed Wine", color: :red, bottle_size_ml: 750,
      price_125ml_cents: 1000, available_glasses: 5, active: true, position: 998
    )
    cart.add(wine_id: doomed_wine.id, glass_size_ml: 125, quantity: 1)
    wine_id = doomed_wine.id
    doomed_wine.destroy!

    assert_empty cart.items
    assert_equal 1, cart.dropped_items.size
    dropped = cart.dropped_items.first
    assert_equal wine_id, dropped.wine_id
    assert_equal :wine_not_found, dropped.reason
  end

  test "a line whose wine became unavailable after being added is dropped and reported" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    assert_empty cart.items
    dropped = cart.dropped_items.first
    assert_equal @gavi.id, dropped.wine_id
    assert_equal :wine_unavailable, dropped.reason
  end

  test "a line whose price was removed after being added is dropped and reported" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)
    @gavi.update!(price_100ml_cents: nil)

    assert_empty cart.items
    dropped = cart.dropped_items.first
    assert_equal @gavi.id, dropped.wine_id
    assert_equal :price_unavailable, dropped.reason
  end

  test "items does not rewrite the session" do
    session = {}
    cart = cart_for(@osteria, session: session)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)
    raw_before = session[:carts].dup

    cart.items

    assert_equal raw_before, session[:carts]
  end

  test "items loads all wines for the cart in a single query" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)

    assert_queries_count(1) { cart.items }
  end

  test "load_cart_data still issues a single query for a multi-line cart once publication is scoped" do
    session = {}
    cart = cart_for(@osteria, session: session)
    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, glass_size_ml: 100, quantity: 1)
    # Smuggle in a line for a wine that was never published, the same way a
    # tampered session cookie would — #items must still filter it out (as a
    # dropped item) without regressing into a per-line lookup.
    session[:carts][@osteria.id.to_s] += [
      { "wine_id" => @unlisted.id, "glass_size_ml" => 125, "quantity" => 1 }
    ]

    assert_queries_count(1) { cart.items }
    assert_equal [ @barolo, @gavi ], cart.items.map(&:wine)
    assert_equal [ @unlisted.id ], cart.dropped_items.map(&:wine_id)
  end

  # --- session shape / no price stored ---

  test "the stored session hash never contains a price" do
    session = {}
    cart = cart_for(@osteria, session: session)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 2)

    line = session[:carts][@osteria.id.to_s].first
    assert_equal(
      { "wine_id" => @barolo.id, "glass_size_ml" => 125, "quantity" => 2 },
      line
    )
    assert_not line.key?("unit_price_cents")
  end

  test "the session stores lines under the restaurant id as a string key" do
    session = {}
    cart = cart_for(@osteria, session: session)

    cart.add(wine_id: @barolo.id, glass_size_ml: 125, quantity: 1)

    assert session[:carts].key?(@osteria.id.to_s)
  end
end
