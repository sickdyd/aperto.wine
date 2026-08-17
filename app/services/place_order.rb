# Turns a session Cart into a persisted Order. Follows the precedent set by
# QrSvgRenderer: a plain service object with a single .call class method.
#
# Wrapped in a single transaction so a diner never ends up with a partial
# order (an Order with some but not all of its OrderItems, or a total that
# does not match its lines).
class PlaceOrder
  # Result of a call. Never raises for a business-rule failure — only for a
  # coding error. The exhaustive error symbol set:
  #
  #   :empty_cart        - the cart has no lines at all (nothing was ever
  #                         added, or everything was already removed)
  #   :items_unavailable  - one or more lines failed the live re-check (the
  #                         wine disappeared, went unavailable, or lost its
  #                         price for that glass size) since being added.
  #                         No order is placed; the cart is left untouched
  #                         so the diner sees exactly which lines dropped.
  #   :order_invalid      - the order or one of its lines failed to save for
  #                         a reason not caught above (defensive: nothing
  #                         in the current model surface should reach this).
  #   :location_out_of_range - the diner's device reported a position outside
  #                         the restaurant's radius. No order is placed and
  #                         the cart is left untouched, so a diner who moves
  #                         closer can retry with the order they already
  #                         built.
  #   :insufficient_stock - a locked re-check at placement found a line's
  #                         quantity exceeds the wine's available_glasses.
  #                         No order is placed and nothing is reserved.
  #
  # `dropped_items` is only ever populated alongside :items_unavailable —
  # the Cart::DroppedItem list that caused the abort, so the caller can tell
  # the diner exactly which lines are blocking them rather than a bare
  # symbol (empty otherwise, including on success).
  Result = Struct.new(:success, :order, :error, :dropped_items, keyword_init: true) do
    def success?
      success
    end
  end

  # Raised inside the transaction to unwind it (rolling back any reservation
  # already made this call) without ever letting a bare business-rule
  # failure escape as an unhandled exception — #call rescues it below and
  # turns it into an ordinary failure(:insufficient_stock) Result.
  InsufficientStock = Class.new(StandardError)

  # Raised when a wine the cart's items reference is gone by the time
  # #reserve_stock! locks it — it existed for Cart#items's live read a
  # moment earlier but was deleted before this transaction's SELECT. Without
  # this, that race surfaces as an unhandled KeyError (or, further down, an
  # FK violation from order_items.create!) — a 500 either way. It maps onto
  # :items_unavailable, which already means exactly this: a line that
  # failed a live re-check.
  WineGoneAtLock = Class.new(StandardError)

  # latitude/longitude/accuracy are the diner's device's own claim about where
  # it is, straight off the browser Geolocation API. They default to nil, and
  # nil is a first-class answer rather than a missing argument: most callers
  # supply no fix at all (the geofence is off by default, and a diner may
  # refuse the browser prompt), and Geofence treats "no usable fix" as a
  # verdict of its own.
  def self.call(cart:, restaurant:, table:, customer:, guest_name:, latitude: nil, longitude: nil, accuracy: nil)
    new(
      cart: cart, restaurant: restaurant, table: table, customer: customer, guest_name: guest_name,
      latitude: latitude, longitude: longitude, accuracy: accuracy
    ).call
  end

  def initialize(cart:, restaurant:, table:, customer:, guest_name:, latitude: nil, longitude: nil, accuracy: nil)
    @cart = cart
    @restaurant = restaurant
    @table = table
    @customer = customer
    @guest_name = guest_name
    @latitude = latitude
    @longitude = longitude
    @accuracy = accuracy
  end

  def call
    # Cart#items/#dropped_items are loaded together from one live query (see
    # Cart#load_cart_data), so reading them here *is* the "re-read every
    # line against live wine state" the order-placement rule requires. Any
    # line that no longer qualifies shows up in dropped_items instead of
    # items — silently ordering the survivors would serve the diner a
    # different order than the one they built, so a non-empty dropped_items
    # aborts the whole placement rather than being ignored.
    return failure(:items_unavailable, dropped_items: cart.dropped_items) if cart.dropped_items.any?
    return failure(:empty_cart) if cart.items.empty?

    # Deliberately last of the guards that run before the transaction opens. A
    # diner whose cart went stale should hear about the cart — that is the
    # problem they can act on — and an empty cart cannot be ordered from at any
    # distance, so neither of those answers should be displaced by a location
    # complaint.
    #
    # Note the ordering also means an out-of-range diner never reaches
    # cart.clear below: the early return leaves the cart exactly as they built
    # it, which is what makes "walk closer and retry" work.
    #
    # It also runs ahead of the stock reservation in build_order! on purpose.
    # Geofence.call is pure arithmetic over attributes already in memory — no
    # query, no lock — whereas reserving takes a row lock on every wine in the
    # cart. Refusing here costs nothing; refusing after the lock would have
    # made every other placement queue behind a request that was never going
    # to be accepted.
    location = Geofence.call(
      restaurant: restaurant, latitude: latitude, longitude: longitude, accuracy: accuracy
    )
    return failure(:location_out_of_range) unless location.allowed?

    order = build_order!(location)
    cart.clear
    success(order)
  rescue ActiveRecord::RecordInvalid
    failure(:order_invalid)
  rescue InsufficientStock
    failure(:insufficient_stock)
  rescue WineGoneAtLock
    failure(:items_unavailable)
  end

  private

  attr_reader :cart, :restaurant, :table, :customer, :guest_name, :latitude, :longitude, :accuracy

  # The verdict is stamped inside the same transaction as the lines, so an
  # order never exists without the location claim that admitted it. Only the
  # derived distance is recorded, never the diner's coordinates — see the
  # migration for why.
  def build_order!(location)
    ActiveRecord::Base.transaction do
      reserve_stock!

      order = restaurant.orders.create!(
        status: :pending, restaurant_table: table, customer: customer, guest_name: guest_name,
        location_status: location.status, distance_meters: location.distance_meters,
        location_accuracy_meters: location.accuracy_meters
      )
      cart.items.each { |item| create_order_item!(order, item) }
      order.calculate_total!
      order
    end
  end

  # The moment of truth: locks every wine the cart touches — in id order, so
  # two concurrent placements over overlapping wines can't deadlock each
  # other — then checks and reserves against those locked rows before any
  # Order or OrderItem exists. Cart's own filtering (dropped_items) already
  # ruled out 0-glass wines; this is the only check for a line whose
  # quantity exceeds what's left, and it must run here, under the lock, not
  # be assumed already done by the caller.
  def reserve_stock!
    wine_ids = cart.items.map { |item| item.wine.id }.uniq
    locked_wines = Wine.where(id: wine_ids).order(:id).lock.index_by(&:id)

    cart.items.each do |item|
      wine = locked_wines[item.wine.id]
      raise WineGoneAtLock if wine.nil?
      raise InsufficientStock if wine.available_glasses < item.quantity

      # Same in-memory wine object across a diner's lines for the same
      # wine (two glass sizes drawing from one pool) — decrement! updates
      # its in-memory attribute too, so the next line's check sees the
      # running total, not a stale snapshot.
      wine.decrement!(:available_glasses, item.quantity)
    end
  end

  # Snapshots unit_price_cents from the wine as it is right now. A later
  # price change must never rewrite a placed order — OrderItem stores its
  # own copy rather than deriving the price from the wine at read time.
  def create_order_item!(order, item)
    order.order_items.create!(
      wine: item.wine,
      glass_size_ml: item.glass_size_ml,
      quantity: item.quantity,
      unit_price_cents: item.unit_price_cents
    )
  end

  def success(order)
    Result.new(success: true, order: order, error: nil, dropped_items: [])
  end

  def failure(error, dropped_items: [])
    Result.new(success: false, order: nil, error: error, dropped_items: dropped_items)
  end
end
