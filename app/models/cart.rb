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
#       { "wine_id" => 7, "serving" => "glass", "glass_size_ml" => 125, "quantity" => 2 },
#       { "wine_id" => 9, "serving" => "bottle", "glass_size_ml" => nil, "quantity" => 1 }
#     ]
#   }
#
# Line identity is the triple (wine_id, serving, glass_size_ml), so the same
# wine can sit in the cart as a bottle and as two different pours at once.
#
# Legacy fallback: lines written before the "serving" key existed have no
# such key at all. Every read path (#items, #dropped_items, and the
# wine_id/serving/glass_size_ml lookups behind #update_quantity and #remove)
# treats a keyless line as "glass" — see #normalized_serving, the single
# place this happens. This is a read-time interpretation only: it never
# rewrites the stored line to add the key (see #items).
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
  #   :invalid_serving     - serving is not one of Wine::SERVINGS (including
  #                          missing or blank)
  #   :wine_unavailable    - the wine exists but Wine#available_for? is false
  #                          for the requested serving (no glasses left for a
  #                          glass line, or no bottle price set for a bottle
  #                          line — see Wine#glasses_available?/#bottle_available?)
  #   :invalid_glass_size  - glass_size_ml is not one of Wine::GLASS_SIZES
  #                          (glass servings only; a bottle's glass_size_ml is
  #                          always coerced to nil, never validated)
  #   :price_unavailable   - the wine has no positive price for that serving —
  #                          nil and zero mean the same thing, "not offered"
  #                          (the same gesture the wine row already reads that
  #                          way; see Wine#price_for)
  #   :cart_full           - adding a new distinct line would exceed
  #                          MAX_DISTINCT_ITEMS (incrementing an existing
  #                          line is still allowed at the cap; a bottle line
  #                          is one distinct item like any other)
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
  DroppedItem = Struct.new(:wine_id, :serving, :glass_size_ml, :quantity, :reason, :wine, keyword_init: true)

  def initialize(session:, restaurant:)
    @session = session
    @restaurant = restaurant
  end

  # Array of CartItem, in insertion order. Silently skips lines whose wine
  # no longer exists, no longer belongs to this restaurant, is no longer
  # published on an active wine list, is no longer available, or has lost
  # its price for that serving — see #dropped_items. Never rewrites the
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

  def add(wine_id:, serving:, glass_size_ml: nil, quantity: 1)
    serving_value = serving.to_s
    return failure(:invalid_serving) unless Wine::SERVINGS.include?(serving_value)

    if serving_value == "bottle"
      # Coerced regardless of what the caller passed — a request smuggling
      # both a bottle serving and a glass size must not store a bottle line
      # carrying a stray glass size.
      glass_size = nil
    else
      glass_size = normalize_glass_size(glass_size_ml)
      return failure(:invalid_glass_size) unless Wine::GLASS_SIZES.include?(glass_size)
    end

    wine = published_wines.find_by(id: wine_id)
    return failure(:wine_not_found) if wine.nil?
    return failure(:wine_unavailable) unless wine.available_for?(serving: serving_value, glass_size_ml: glass_size)
    return failure(:price_unavailable) unless positive_price?(wine, serving_value, glass_size)

    lines = stored_lines
    index = line_index(lines, wine.id, serving_value, glass_size)
    # Clamp the raw input itself, not just the resulting sum — otherwise a
    # negative quantity (however it reached here) reads as a silent
    # decrement of an existing line instead of "add at least one".
    requested_quantity = clamp_quantity(quantity.to_i)

    if index
      new_lines = replace_line(lines, index, quantity: clamp_quantity(lines[index]["quantity"] + requested_quantity))
    else
      return failure(:cart_full) if lines.size >= MAX_DISTINCT_ITEMS

      new_lines = lines + [ new_line(wine.id, serving_value, glass_size, requested_quantity) ]
    end

    persist(new_lines)
    success
  end

  def update_quantity(wine_id:, serving:, glass_size_ml:, quantity:)
    lines = stored_lines
    index = line_index(lines, wine_id.to_i, serving.to_s, normalize_glass_size(glass_size_ml))
    return failure(:wine_not_found) if index.nil?

    new_lines = if quantity.to_i <= 0
      remove_line(lines, index)
    else
      replace_line(lines, index, quantity: clamp_quantity(quantity.to_i))
    end

    persist(new_lines)
    success
  end

  def remove(wine_id:, serving:, glass_size_ml:)
    lines = stored_lines
    index = line_index(lines, wine_id.to_i, serving.to_s, normalize_glass_size(glass_size_ml))
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

  # The single place a stored line with no "serving" key (written before
  # this key existed) is read as a glass — every read path funnels through
  # here, so a legacy keyless line is still found by a "glass" lookup and
  # rendered as a glass line. Never used to rewrite the stored line itself.
  def normalized_serving(line)
    line["serving"] || "glass"
  end

  def normalize_glass_size(glass_size_ml)
    glass_size_ml.nil? ? nil : glass_size_ml.to_i
  end

  def line_index(lines, wine_id, serving, glass_size_ml)
    lines.find_index do |line|
      line["wine_id"] == wine_id &&
        normalized_serving(line) == serving &&
        line["glass_size_ml"] == glass_size_ml
    end
  end

  def new_line(wine_id, serving, glass_size_ml, quantity)
    { "wine_id" => wine_id, "serving" => serving, "glass_size_ml" => glass_size_ml, "quantity" => quantity }
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
      serving = normalized_serving(line)
      reason = drop_reason(wine, serving, line["glass_size_ml"])
      if reason
        dropped << DroppedItem.new(
          wine_id: line["wine_id"], serving: serving, glass_size_ml: line["glass_size_ml"],
          quantity: line["quantity"], reason: reason, wine: wine
        )
      else
        kept << CartItem.new(wine: wine, serving: serving, glass_size_ml: line["glass_size_ml"], quantity: line["quantity"])
      end
    end

    @items = kept
    @dropped_items = dropped
    @cart_data_loaded = true
  end

  # nil means the line still qualifies; otherwise the symbol is the reason
  # it was dropped (see DroppedItem).
  def drop_reason(wine, serving, glass_size_ml)
    return :wine_not_found if wine.nil?
    return :wine_unavailable unless wine.available_for?(serving: serving, glass_size_ml: glass_size_ml)
    return :price_unavailable unless positive_price?(wine, serving, glass_size_ml)

    nil
  end

  # A zero price means exactly the same thing as no price at all: this
  # serving is not offered. Treating them differently is what let a stale
  # line with a zeroed-out price render blank and silently drop out of the
  # total instead of being reported to the diner.
  def positive_price?(wine, serving, glass_size_ml)
    price = wine.price_for(serving: serving, glass_size_ml: glass_size_ml)
    price.present? && price.positive?
  end
end
