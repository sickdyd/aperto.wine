# A per-restaurant shopping cart held entirely in the session — there is no
# carts table and there will not be one. Follows the precedent of
# TableBulkGeneration: a plain, non-ActiveRecord object living in
# app/models.
#
# Session shape (see MenusController#remember_table for the same
# restaurant_id.to_s => value precedent):
#
#   session[:carts] = {
#     "42" => [
#       { "wine_id" => 7, "glass_size_ml" => 125, "quantity" => 2 }
#     ]
#   }
#
# The session is serialized to JSON, so only string keys and integer
# values are ever written or trusted back out of it. Prices are never
# written to the session — Cart#items always re-reads the current price
# from the Wine, so a tampered cookie cannot dictate a price.
#
# Every mutation (add/update_quantity/remove/clear) assigns a new
# array/hash back into the session rather than mutating the existing
# structure in place.
class Cart
  MAX_QUANTITY_PER_ITEM = 20
  MAX_DISTINCT_ITEMS = 25

  # Result of a mutation (#add, #update_quantity, #remove). Never raises on
  # bad input and never carries an i18n string — the controller maps
  # #error onto a flash message. The documented, exhaustive symbol set:
  #
  #   :wine_not_found     - no such wine, it belongs to another restaurant, or
  #                          it is not published on any of this restaurant's
  #                          active wine lists (deliberately not distinguished
  #                          from "does not exist" — that would leak which
  #                          wines the owner has chosen not to show)
  #   :wine_unavailable    - the wine exists but Wine#available? is false
  #   :invalid_glass_size  - glass_size_ml is not one of Wine::GLASS_SIZES
  #   :price_unavailable   - the wine has no positive price for that glass
  #                          size — nil and zero mean the same thing, "not
  #                          offered" (the same gesture the wine row already
  #                          reads that way; see Wine#price_for_glass)
  #   :cart_full           - adding a new distinct line would exceed
  #                          MAX_DISTINCT_ITEMS (incrementing an existing
  #                          line is still allowed at the cap)
  #   :insufficient_stock  - the wine's combined quantity across all of this
  #                          cart's lines for it (every glass size, not just
  #                          the line being touched — see
  #                          #over_stock_wine_ids) would exceed
  #                          available_glasses (0 available_glasses is
  #                          :wine_unavailable instead — see Wine#available?)
  Result = Struct.new(:success, :error, keyword_init: true) do
    def success?
      success
    end
  end

  # One line skipped while reading a stale cart (see #items). `reason` is
  # drawn from the same symbol set as Result#error. `wine` is the live Wine
  # when it could still be resolved (dropped for :wine_unavailable or
  # :price_unavailable) and nil when it could not (:wine_not_found — the
  # wine was deleted, un-published, or never belonged to this restaurant) —
  # a view rendering a dropped line must handle the nil case with a neutral
  # fallback rather than crash.
  DroppedItem = Struct.new(:wine_id, :glass_size_ml, :quantity, :reason, :wine, keyword_init: true)

  def initialize(session:, restaurant:)
    @session = session
    @restaurant = restaurant
  end

  # Array of CartItem, in insertion order. Silently skips lines whose wine
  # no longer exists, no longer belongs to this restaurant, is no longer
  # published on an active wine list, is no longer available, or has lost
  # its price for that size — see #dropped_items. Never rewrites the
  # session: a read has no side effects.
  def items
    load_cart_data
    @items
  end

  # Lines skipped by the most recent #items read, so a view can tell the
  # diner their order changed.
  def dropped_items
    load_cart_data
    @dropped_items
  end

  def add(wine_id:, glass_size_ml:, quantity: 1)
    glass_size = glass_size_ml.to_i
    return failure(:invalid_glass_size) unless Wine::GLASS_SIZES.include?(glass_size)

    wine = published_wines.find_by(id: wine_id)
    return failure(:wine_not_found) if wine.nil?
    return failure(:wine_unavailable) unless wine.available?
    return failure(:price_unavailable) unless positive_price?(wine, glass_size)

    lines = stored_lines
    index = line_index(lines, wine.id, glass_size)
    # Clamp the raw input itself, not just the resulting sum — otherwise a
    # negative quantity (however it reached here) reads as a silent
    # decrement of an existing line instead of "add at least one".
    requested_quantity = clamp_quantity(quantity.to_i)
    # Stock is a per-wine pool, not a per-line one — a wine offered at two
    # glass sizes draws from the same available_glasses, so the check must
    # add in every other line already in the cart for this wine, not just
    # the line being touched (see #over_stock_wine_ids).
    other_quantity = other_lines_quantity(lines, wine.id, excluding_index: index)

    if index
      new_quantity = clamp_quantity(lines[index]["quantity"] + requested_quantity)
      return failure(:insufficient_stock) if other_quantity + new_quantity > wine.available_glasses

      new_lines = replace_line(lines, index, quantity: new_quantity)
    else
      return failure(:cart_full) if lines.size >= MAX_DISTINCT_ITEMS
      return failure(:insufficient_stock) if other_quantity + requested_quantity > wine.available_glasses

      new_lines = lines + [ new_line(wine.id, glass_size, requested_quantity) ]
    end

    persist(new_lines)
    success
  end

  def update_quantity(wine_id:, glass_size_ml:, quantity:)
    lines = stored_lines
    index = line_index(lines, wine_id.to_i, glass_size_ml.to_i)
    return failure(:wine_not_found) if index.nil?

    new_lines = if quantity.to_i <= 0
      remove_line(lines, index)
    else
      new_quantity = clamp_quantity(quantity.to_i)
      # published_wines, not the bare tenant association — the same
      # publication boundary #add enforces, so a wine that went inactive or
      # was un-published answers a quantity bump the same way #add would
      # (left to #items/#dropped_items to report, not misreported here as a
      # stock problem).
      wine = published_wines.find_by(id: wine_id.to_i)
      if wine
        other_quantity = other_lines_quantity(lines, wine.id, excluding_index: index)
        return failure(:insufficient_stock) if other_quantity + new_quantity > wine.available_glasses
      end

      replace_line(lines, index, quantity: new_quantity)
    end

    persist(new_lines)
    success
  end

  def remove(wine_id:, glass_size_ml:)
    lines = stored_lines
    index = line_index(lines, wine_id.to_i, glass_size_ml.to_i)
    persist(index ? remove_line(lines, index) : lines)
    success
  end

  # Empties only this restaurant's cart, leaving other restaurants' carts
  # in the session untouched.
  def clear
    persist([])
  end

  def total_cents
    items.sum(&:subtotal_cents)
  end

  def item_count
    items.sum(&:quantity)
  end

  def empty?
    items.empty?
  end

  # True whenever the session holds any line for this restaurant at all,
  # dropped or not — distinct from #empty?, which only counts orderable
  # lines. A cart can be #empty? while still holding a dropped line (e.g.
  # its only wine went unavailable); the view needs this predicate, not
  # #empty?, to decide whether the "Empty cart" control has anything to do.
  # A pure read of the raw session, so it never triggers the wines query
  # #items/#dropped_items do.
  def any_lines?
    stored_lines.any?
  end

  # True when nothing blocks placing the cart as it reads right now: no line
  # was dropped on this read, and no wine's combined quantity across its
  # lines outruns its current available_glasses. Distinct from #empty?
  # (line count only) — a cart can hold nothing but resolvable lines and
  # still be unorderable because stock fell out from under one of them.
  #
  # Vacuously true for an empty cart (no dropped items, no over-stock wines
  # to speak of) — deliberately not folded into "has anything to order".
  # Pair with #items.any? / #empty? when the view needs to tell "nothing
  # here yet" apart from "something here is blocked".
  def orderable?
    dropped_items.empty? && over_stock_wine_ids.empty?
  end

  # Ids of wines whose combined quantity across every line in this cart —
  # every glass size, not just one — exceeds their current
  # available_glasses. A wine offered at two sizes draws from one stock
  # pool, so this is the single answer #add, #update_quantity and
  # #orderable? all agree on; a wine can appear here even with just one
  # line, if that line alone outruns stock.
  def over_stock_wine_ids
    load_cart_data
    @over_stock_wine_ids
  end

  private

  attr_reader :session, :restaurant

  def restaurant_key
    restaurant.id.to_s
  end

  # The same publication boundary the public menu enforces
  # (MenusController#show / WineList.published): a wine is orderable only if it
  # sits on at least one of this restaurant's active wine lists. A wine on no
  # list, or only on unpublished lists, must be as unreachable to the cart as
  # it is to the menu — the owner's "Published" toggle is otherwise cosmetic.
  # `distinct` guards against a wine published on more than one active list
  # producing duplicate rows from the join.
  def published_wines
    restaurant.wines.joins(:wine_lists).merge(WineList.published).distinct
  end

  def all_carts
    session[:carts] || {}
  end

  def stored_lines
    all_carts[restaurant_key] || []
  end

  def persist(lines)
    session[:carts] = all_carts.merge(restaurant_key => lines)
    @cart_data_loaded = false
  end

  def line_index(lines, wine_id, glass_size)
    lines.find_index { |line| line["wine_id"] == wine_id && line["glass_size_ml"] == glass_size }
  end

  # Total quantity already in the cart for this wine across every glass
  # size, excluding the line at excluding_index (the line #add or
  # #update_quantity is about to replace, so it isn't counted twice
  # alongside its own resulting quantity). nil excludes nothing — correct
  # when there is no existing line yet for the glass size being touched.
  def other_lines_quantity(lines, wine_id, excluding_index:)
    lines.each_with_index.sum do |line, i|
      next 0 if i == excluding_index || line["wine_id"] != wine_id

      line["quantity"]
    end
  end

  def new_line(wine_id, glass_size, quantity)
    { "wine_id" => wine_id, "glass_size_ml" => glass_size, "quantity" => quantity }
  end

  def replace_line(lines, index, quantity:)
    lines.each_with_index.map { |line, i| i == index ? line.merge("quantity" => quantity) : line }
  end

  def remove_line(lines, index)
    lines.each_with_index.reject { |_line, i| i == index }.map(&:first)
  end

  def clamp_quantity(quantity)
    quantity.clamp(1, MAX_QUANTITY_PER_ITEM)
  end

  def success
    Result.new(success: true, error: nil)
  end

  def failure(error)
    Result.new(success: false, error: error)
  end

  # Loads every wine referenced by this cart in a single query, then
  # partitions lines into kept CartItems and dropped lines. Memoized per
  # mutation so #items and #dropped_items called back to back only query
  # once, but never used to avoid re-checking freshness across mutations.
  def load_cart_data
    return if @cart_data_loaded

    lines = stored_lines
    wines_by_id = published_wines.where(id: lines.map { |line| line["wine_id"] }).index_by(&:id)

    kept = []
    dropped = []
    lines.each do |line|
      wine = wines_by_id[line["wine_id"]]
      reason = drop_reason(wine, line["glass_size_ml"])
      if reason
        dropped << DroppedItem.new(
          wine_id: line["wine_id"], glass_size_ml: line["glass_size_ml"],
          quantity: line["quantity"], reason: reason, wine: wine
        )
      else
        kept << CartItem.new(wine: wine, glass_size_ml: line["glass_size_ml"], quantity: line["quantity"])
      end
    end

    @items = kept
    @dropped_items = dropped
    @over_stock_wine_ids = kept
      .group_by { |item| item.wine.id }
      .select { |_wine_id, wine_items| wine_items.sum(&:quantity) > wine_items.first.wine.available_glasses }
      .keys
    @cart_data_loaded = true
  end

  # nil means the line still qualifies; otherwise the symbol is the reason
  # it was dropped (see DroppedItem).
  def drop_reason(wine, glass_size_ml)
    return :wine_not_found if wine.nil?
    return :wine_unavailable unless wine.available?
    return :price_unavailable unless positive_price?(wine, glass_size_ml)

    nil
  end

  # A zero price means exactly the same thing as no price at all: this size
  # is not offered. Treating them differently is what let a stale line with
  # a zeroed-out price render blank and silently drop out of the total
  # instead of being reported to the diner.
  def positive_price?(wine, glass_size_ml)
    price = wine.price_for_glass(glass_size_ml)
    price.present? && price.positive?
  end
end
