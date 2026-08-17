require "test_helper"

class CartTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @barolo = wines(:barolo)
    @gavi = wines(:gavi)
    @sold_out = wines(:sold_out_wine)
    @franciacorta = wines(:trattoria_franciacorta)
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

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)

    assert_equal [ @barolo, @gavi ], cart.items.map(&:wine)
    assert_equal [ 125, 100 ], cart.items.map(&:glass_size_ml)
    assert_equal [ 2, 1 ], cart.items.map(&:quantity)
  end

  test "add returns a successful result" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert result.success?
    assert_nil result.error
  end

  test "add rejects a wine belonging to another restaurant" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @franciacorta.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
    assert_empty cart.items
  end

  test "add rejects a wine id that does not exist" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: -1, serving: "glass", glass_size_ml: 125, quantity: 1)

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

    result = cart.add(wine_id: @inactive_list_only.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
    assert_empty cart.items
  end

  test "add rejects a wine that belongs to no list at all" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @unlisted.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
    assert_empty cart.items
  end

  test "a normally published wine still adds and reads back fine" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert result.success?
    assert_equal [ @barolo ], cart.items.map(&:wine)
  end

  # --- zero price means "not offered", same as no price at all (final review finding 2) ---

  test "add rejects a zero price the same as no price at all" do
    cart = cart_for(@osteria)

    # barolo's 150ml price is fixtured at 0 cents, the same gesture an owner
    # uses to stop offering a size.
    result = cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 150, quantity: 1)

    assert_not result.success?
    assert_equal :price_unavailable, result.error
    assert_empty cart.items
  end

  test "a line whose price falls to zero after being added is dropped as price_unavailable, same as losing its price entirely" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)

    @gavi.update!(price_100ml_cents: 0)

    assert_empty cart.items
    assert_equal 1, cart.dropped_items.size
    dropped = cart.dropped_items.first
    assert_equal @gavi.id, dropped.wine_id
    assert_equal :price_unavailable, dropped.reason
  end

  test "a wine added while published is dropped on read once its list is un-published" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    wine_lists(:osteria_list).update!(published: false)

    assert_empty cart.items
    assert_equal 1, cart.dropped_items.size
    dropped = cart.dropped_items.first
    assert_equal @barolo.id, dropped.wine_id
    assert_equal :wine_not_found, dropped.reason
  end

  test "add rejects an unavailable wine" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @sold_out.id, serving: "glass", glass_size_ml: 100, quantity: 1)

    assert_not result.success?
    assert_equal :wine_unavailable, result.error
    assert_empty cart.items
  end

  test "add rejects a glass size outside Wine::GLASS_SIZES" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 60, quantity: 1)

    assert_not result.success?
    assert_equal :invalid_glass_size, result.error
    assert_empty cart.items
  end

  test "add rejects a glass size the wine has no price for" do
    cart = cart_for(@osteria)

    # gavi has no price_75ml_cents set on the fixture
    result = cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 75, quantity: 1)

    assert_not result.success?
    assert_equal :price_unavailable, result.error
    assert_empty cart.items
  end

  test "add clamps quantity above the max down to MAX_QUANTITY_PER_ITEM" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 999)

    assert_equal Cart::MAX_QUANTITY_PER_ITEM, cart.items.first.quantity
  end

  test "add clamps a zero or negative quantity up to 1" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 0)

    assert_equal 1, cart.items.first.quantity
  end

  test "re-adding the same wine and glass size merges into the existing line" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3)

    assert_equal 1, cart.items.size
    assert_equal 5, cart.items.first.quantity
  end

  test "adding a different glass size for the same wine creates a separate line" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 100, quantity: 1)

    assert_equal 2, cart.items.size
  end

  test "a merged quantity is clamped to MAX_QUANTITY_PER_ITEM" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 15)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 15)

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
    wines.each { |wine| cart.add(wine_id: wine.id, serving: "glass", glass_size_ml: 125, quantity: 1) }
    assert_equal Cart::MAX_DISTINCT_ITEMS, cart.items.size

    extra = create_published_wine(
      name: "One Too Many", color: :red, bottle_size_ml: 750,
      price_125ml_cents: 1000, available_glasses: 5, active: true, position: 999
    )
    result = cart.add(wine_id: extra.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :cart_full, result.error
    assert_equal Cart::MAX_DISTINCT_ITEMS, cart.items.size

    increment_result = cart.add(wine_id: wines.first.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert increment_result.success?
    assert_equal 2, cart.items.first.quantity
  end

  # --- bottles ---

  test "add stores a bottle line with glass_size_ml stored as nil" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 1)

    assert result.success?
    item = cart.items.first
    assert_equal "bottle", item.serving
    assert_nil item.glass_size_ml
  end

  test "a bottle add coerces a stray glass_size_ml to nil rather than storing it" do
    session = {}
    cart = cart_for(@osteria, session: session)

    cart.add(wine_id: @barolo.id, serving: "bottle", glass_size_ml: 125, quantity: 1)

    line = session[:carts][@osteria.id.to_s].first
    assert_equal "bottle", line["serving"]
    assert_nil line["glass_size_ml"]
  end

  test "a bottle and two different pours of the same wine coexist as three separate lines" do
    cart = cart_for(@osteria)

    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 1)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 100, quantity: 1)

    assert_equal 3, cart.items.size
    assert_equal [ "bottle", "glass", "glass" ], cart.items.map(&:serving)
  end

  test "add rejects a missing serving" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, serving: nil, glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :invalid_serving, result.error
    assert_empty cart.items
  end

  test "add rejects a blank serving" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, serving: "", glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :invalid_serving, result.error
    assert_empty cart.items
  end

  test "add rejects a bogus serving" do
    cart = cart_for(@osteria)

    result = cart.add(wine_id: @barolo.id, serving: "keg", glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :invalid_serving, result.error
    assert_empty cart.items
  end

  # :wine_unavailable, not :price_unavailable, is the correct symbol here —
  # not an oversight. Unlike a glass, a bottle has no separate stock column;
  # a positive price_bottle_cents is the *only* signal that the restaurant
  # sells this wine by the bottle at all, so Wine#bottle_available? folds
  # price into availability itself. Cart#add's availability check (step 4)
  # therefore always fails before the price check (step 5) is ever reached
  # for a priceless bottle, making :price_unavailable structurally
  # unreachable here — it reads as :wine_unavailable, the same as the
  # inactive-wine case below (both go through the same
  # Wine#available_for? gate). The existing cart.errors.price_unavailable
  # copy is independent evidence this is intentional: "That wine has no
  # price set for that glass size." is glass-specific and would be wrong
  # copy for a bottle.
  test "add rejects a bottle whose wine has no bottle price set" do
    cart = cart_for(@osteria)

    # gavi has no price_bottle_cents set on the fixture
    result = cart.add(wine_id: @gavi.id, serving: "bottle", quantity: 1)

    assert_not result.success?
    assert_equal :wine_unavailable, result.error
    assert_empty cart.items
  end

  test "add rejects a bottle whose wine has a zero bottle price, the same as no price at all" do
    cart = cart_for(@osteria)
    zero_priced = create_published_wine(
      name: "Zero Priced Bottle", color: :red, bottle_size_ml: 750,
      price_bottle_cents: 0, available_glasses: 5, active: true, position: 996
    )

    result = cart.add(wine_id: zero_priced.id, serving: "bottle", quantity: 1)

    assert_not result.success?
    assert_equal :wine_unavailable, result.error
    assert_empty cart.items
  end

  # Same conflation as #add above, on the post-add re-check path this time:
  # drop_reason has the identical step ordering (available_for? before
  # price_for), so a bottle already in the cart whose price is cleared or
  # zeroed afterwards also drops as :wine_unavailable, never
  # :price_unavailable. This is the path PlaceOrder relies on to abort a
  # placement when a bottle loses its price between add and checkout.
  test "a bottle line whose price is cleared after being added is dropped as wine_unavailable, not price_unavailable" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "bottle", quantity: 1)

    @barolo.update!(price_bottle_cents: 0)

    assert_empty cart.items
    assert_equal 1, cart.dropped_items.size
    dropped = cart.dropped_items.first
    assert_equal @barolo.id, dropped.wine_id
    assert_equal "bottle", dropped.serving
    assert_equal :wine_unavailable, dropped.reason
  end

  test "add rejects a bottle on an inactive wine" do
    cart = cart_for(@osteria)
    inactive_wine = create_published_wine(
      name: "Inactive Bottle Wine", color: :red, bottle_size_ml: 750,
      price_bottle_cents: 5000, available_glasses: 5, active: false, position: 995
    )

    result = cart.add(wine_id: inactive_wine.id, serving: "bottle", quantity: 1)

    assert_not result.success?
    assert_equal :wine_unavailable, result.error
    assert_empty cart.items
  end

  # The Task 1 regression this guards: Wine#available? widened to "orderable
  # in some form" (glass OR bottle), but Cart must still use the
  # serving-specific predicate — a wine with zero glasses left but a bottle
  # price must not let a glass line through.
  test "a glass line for a wine with zero glasses but a positive bottle price is rejected as wine_unavailable" do
    cart = cart_for(@osteria)
    bottle_only = create_published_wine(
      name: "Bottle Only Wine", color: :red, bottle_size_ml: 750,
      price_bottle_cents: 8000, price_125ml_cents: 2000, available_glasses: 0, active: true, position: 994
    )

    result = cart.add(wine_id: bottle_only.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert_not result.success?
    assert_equal :wine_unavailable, result.error
    assert_empty cart.items
  end

  test "a glass line for a wine with zero glasses but a positive bottle price is dropped on read, not silently priced" do
    bottle_only = create_published_wine(
      name: "Bottle Only Wine Two", color: :red, bottle_size_ml: 750,
      price_bottle_cents: 8000, price_125ml_cents: 2000, available_glasses: 5, active: true, position: 993
    )
    cart = cart_for(@osteria)
    cart.add(wine_id: bottle_only.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    bottle_only.update!(available_glasses: 0)

    assert_empty cart.items
    dropped = cart.dropped_items.first
    assert_equal bottle_only.id, dropped.wine_id
    assert_equal :wine_unavailable, dropped.reason
  end

  # --- legacy session lines with no "serving" key ---

  test "a legacy line with no serving key reads as a glass" do
    session = {}
    cart = cart_for(@osteria, session: session)
    session[:carts] = { @osteria.id.to_s => [
      { "wine_id" => @barolo.id, "glass_size_ml" => 125, "quantity" => 1 }
    ] }

    item = cart.items.first
    assert_equal "glass", item.serving
    assert_equal 125, item.glass_size_ml
  end

  test "a legacy keyless line is found by line_index when looking up (glass, 125)" do
    session = {}
    cart = cart_for(@osteria, session: session)
    session[:carts] = { @osteria.id.to_s => [
      { "wine_id" => @barolo.id, "glass_size_ml" => 125, "quantity" => 1 }
    ] }

    result = cart.update_quantity(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 3)

    assert result.success?
    assert_equal 3, cart.items.first.quantity
  end

  test "reading a legacy keyless line does not rewrite the session to add the serving key" do
    session = {}
    cart = cart_for(@osteria, session: session)
    session[:carts] = { @osteria.id.to_s => [
      { "wine_id" => @barolo.id, "glass_size_ml" => 125, "quantity" => 1 }
    ] }
    raw_before = session[:carts].dup

    cart.items

    assert_equal raw_before, session[:carts]
    assert_not session[:carts][@osteria.id.to_s].first.key?("serving")
  end

  # --- update_quantity ---

  test "update_quantity changes an existing line's quantity" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = cart.update_quantity(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 4)

    assert result.success?
    assert_equal 4, cart.items.first.quantity
  end

  test "update_quantity clamps the new quantity to MAX_QUANTITY_PER_ITEM" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    cart.update_quantity(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 999)

    assert_equal Cart::MAX_QUANTITY_PER_ITEM, cart.items.first.quantity
  end

  test "update_quantity to zero removes the line" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    result = cart.update_quantity(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 0)

    assert result.success?
    assert_empty cart.items
  end

  test "update_quantity to a negative number removes the line" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    cart.update_quantity(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: -3)

    assert_empty cart.items
  end

  test "update_quantity on a line that is not in the cart fails without raising" do
    cart = cart_for(@osteria)

    result = cart.update_quantity(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)

    assert_not result.success?
    assert_equal :wine_not_found, result.error
  end

  # --- remove ---

  test "remove drops the matching line" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)

    result = cart.remove(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125)

    assert result.success?
    assert_equal [ @gavi ], cart.items.map(&:wine)
  end

  test "remove on a line that is not present is a harmless no-op" do
    cart = cart_for(@osteria)

    result = cart.remove(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125)

    assert result.success?
    assert_empty cart.items
  end

  # --- totals ---

  test "total_cents and item_count sum across multiple lines" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 3)

    expected_total = (@barolo.price_for_glass(125) * 2) + (@gavi.price_for_glass(100) * 3)

    assert_equal expected_total, cart.total_cents
    assert_equal 5, cart.item_count
  end

  test "empty? reflects whether the cart has any lines" do
    cart = cart_for(@osteria)
    assert cart.empty?

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    assert_not cart.empty?
  end

  # --- clear and multi-restaurant isolation ---

  test "two restaurants' carts stay independent in one session" do
    session = {}
    osteria_cart = cart_for(@osteria, session: session)
    trattoria_cart = cart_for(@trattoria, session: session)

    osteria_cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    trattoria_cart.add(wine_id: @franciacorta.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert_equal [ @barolo ], osteria_cart.items.map(&:wine)
    assert_equal [ @franciacorta ], trattoria_cart.items.map(&:wine)
  end

  test "clear empties only this restaurant's cart, leaving the other restaurant's cart intact" do
    session = {}
    osteria_cart = cart_for(@osteria, session: session)
    trattoria_cart = cart_for(@trattoria, session: session)
    osteria_cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    trattoria_cart.add(wine_id: @franciacorta.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    osteria_cart.clear

    assert_empty osteria_cart.items
    assert_equal [ @franciacorta ], trattoria_cart.items.map(&:wine)
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
    cart.add(wine_id: doomed_wine.id, serving: "glass", glass_size_ml: 125, quantity: 1)
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
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    assert_empty cart.items
    dropped = cart.dropped_items.first
    assert_equal @gavi.id, dropped.wine_id
    assert_equal :wine_unavailable, dropped.reason
  end

  test "a line whose price was removed after being added is dropped and reported" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(price_100ml_cents: nil)

    assert_empty cart.items
    dropped = cart.dropped_items.first
    assert_equal @gavi.id, dropped.wine_id
    assert_equal :price_unavailable, dropped.reason
  end

  # --- recovering from a dropped line (final review finding 1) ---

  test "a dropped item carries the wine when it is still resolvable, so the view can render it" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    dropped = cart.dropped_items.first
    assert_equal @gavi, dropped.wine
  end

  test "a dropped item has no wine when it can no longer be resolved at all" do
    session = {}
    cart = cart_for(@osteria, session: session)
    doomed_wine = create_published_wine(
      name: "Doomed Wine Two", color: :red, bottle_size_ml: 750,
      price_125ml_cents: 1000, available_glasses: 5, active: true, position: 997
    )
    cart.add(wine_id: doomed_wine.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    doomed_wine.destroy!

    dropped = cart.dropped_items.first
    assert_nil dropped.wine
  end

  test "any_lines? is true even once every line in the cart has been dropped" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)

    assert cart.empty?
    assert cart.any_lines?
  end

  test "any_lines? is false when the session holds no line for this restaurant at all" do
    cart = cart_for(@osteria)

    assert_not cart.any_lines?
  end

  test "remove clears a dropped line, recovering a cart that would otherwise be stuck" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)
    assert cart.any_lines?

    result = cart.remove(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100)

    assert result.success?
    assert_not cart.any_lines?
    assert_empty cart.dropped_items
  end

  # --- add clamps its own input, not just the resulting sum (final review finding 7) ---

  test "add clamps a negative quantity input rather than silently decrementing an existing line" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 5)

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: -4)

    # The negative input is clamped to 1 before being added to the existing
    # line (5 + 1 = 6), not treated as a decrement (5 + -4 = 1).
    assert_equal 6, cart.items.first.quantity
  end

  test "items does not rewrite the session" do
    session = {}
    cart = cart_for(@osteria, session: session)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
    @gavi.update!(available_glasses: 0)
    raw_before = session[:carts].dup

    cart.items

    assert_equal raw_before, session[:carts]
  end

  test "items loads all wines for the cart in a single query" do
    cart = cart_for(@osteria)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)

    assert_queries_count(1) { cart.items }
  end

  test "load_cart_data still issues a single query for a multi-line cart once publication is scoped" do
    session = {}
    cart = cart_for(@osteria, session: session)
    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)
    cart.add(wine_id: @gavi.id, serving: "glass", glass_size_ml: 100, quantity: 1)
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

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 2)

    line = session[:carts][@osteria.id.to_s].first
    assert_equal(
      { "wine_id" => @barolo.id, "serving" => "glass", "glass_size_ml" => 125, "quantity" => 2 },
      line
    )
    assert_not line.key?("unit_price_cents")
  end

  test "the session stores lines under the restaurant id as a string key" do
    session = {}
    cart = cart_for(@osteria, session: session)

    cart.add(wine_id: @barolo.id, serving: "glass", glass_size_ml: 125, quantity: 1)

    assert session[:carts].key?(@osteria.id.to_s)
  end
end
