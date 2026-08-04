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
  Result = Struct.new(:success, :order, :error, keyword_init: true) do
    def success?
      success
    end
  end

  def self.call(cart:, restaurant:, table:, customer:, guest_name:)
    new(cart: cart, restaurant: restaurant, table: table, customer: customer, guest_name: guest_name).call
  end

  def initialize(cart:, restaurant:, table:, customer:, guest_name:)
    @cart = cart
    @restaurant = restaurant
    @table = table
    @customer = customer
    @guest_name = guest_name
  end

  def call
    # Cart#items/#dropped_items are loaded together from one live query (see
    # Cart#load_cart_data), so reading them here *is* the "re-read every
    # line against live wine state" the order-placement rule requires. Any
    # line that no longer qualifies shows up in dropped_items instead of
    # items — silently ordering the survivors would serve the diner a
    # different order than the one they built, so a non-empty dropped_items
    # aborts the whole placement rather than being ignored.
    return failure(:items_unavailable) if cart.dropped_items.any?
    return failure(:empty_cart) if cart.items.empty?

    order = build_order!
    cart.clear
    success(order)
  rescue ActiveRecord::RecordInvalid
    failure(:order_invalid)
  end

  private

  attr_reader :cart, :restaurant, :table, :customer, :guest_name

  def build_order!
    ActiveRecord::Base.transaction do
      order = restaurant.orders.create!(
        status: :pending, restaurant_table: table, customer: customer, guest_name: guest_name
      )
      cart.items.each { |item| create_order_item!(order, item) }
      order.calculate_total!
      order
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
    Result.new(success: true, order: order, error: nil)
  end

  def failure(error)
    Result.new(success: false, order: nil, error: error)
  end
end
