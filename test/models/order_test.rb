require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def valid_attributes
    {
      restaurant: restaurants(:osteria),
      customer: users(:customer),
      status: :pending,
      total_amount_cents: 0
    }
  end

  # --- Validations ---

  test "creates a valid order" do
    order = Order.new(valid_attributes)
    assert order.valid?
  end

  test "requires restaurant" do
    order = Order.new(valid_attributes.merge(restaurant: nil))
    assert_not order.valid?
  end

  test "allows a nil customer (guest order)" do
    order = Order.new(valid_attributes.merge(customer: nil))
    assert order.valid?
  end

  test "requires total_amount_cents >= 0" do
    order = Order.new(valid_attributes.merge(total_amount_cents: -1))
    assert_not order.valid?
    assert order.errors.of_kind?(:total_amount_cents, :greater_than_or_equal_to)
  end

  test "allows total_amount_cents of zero" do
    order = Order.new(valid_attributes.merge(total_amount_cents: 0))
    assert order.valid?
  end

  test "guest_name is optional" do
    order = Order.new(valid_attributes.merge(customer: nil, guest_name: nil))
    assert order.valid?
  end

  test "guest_name is capped at 64 characters" do
    order = Order.new(valid_attributes.merge(guest_name: "a" * 65))
    assert_not order.valid?
    assert order.errors.of_kind?(:guest_name, :too_long)
  end

  test "guest_name of exactly 64 characters is valid" do
    order = Order.new(valid_attributes.merge(guest_name: "a" * 64))
    assert order.valid?
  end

  # --- Enums ---

  test "status enum values" do
    assert_equal 0, Order.statuses[:pending]
    assert_equal 1, Order.statuses[:approved]
    assert_equal 2, Order.statuses[:cancelled]
    assert_equal 3, Order.statuses[:completed]
  end

  test "status predicate methods work" do
    assert orders(:pending_order).pending?
    assert orders(:approved_order).approved?
  end

  test "location_status enum values" do
    assert_equal 0, Order.location_statuses[:not_checked]
    assert_equal 1, Order.location_statuses[:verified]
    assert_equal 2, Order.location_statuses[:unverified]
  end

  # Every order placed before the geofence existed, and every order at a
  # restaurant that leaves it off, has to read as "no claim made" rather than as
  # a failed check — so the column default is what the owner sees.
  test "location_status defaults to not_checked" do
    assert_equal "not_checked", Order.new.location_status
    assert_equal "not_checked", Order.create!(valid_attributes).location_status
  end

  # The prefix is not cosmetic: unprefixed, `verified?` would sit next to the
  # `status` enum's own predicates with nothing to say which one it answers.
  test "location_status predicates are prefixed" do
    order = Order.new(valid_attributes.merge(location_status: :verified))

    assert order.location_status_verified?
    assert_not order.location_status_not_checked?
    assert_not order.location_status_unverified?
  end

  test "location_status scopes are prefixed" do
    verified = Order.create!(valid_attributes.merge(location_status: :verified))
    unverified = Order.create!(valid_attributes.merge(location_status: :unverified))

    assert_includes Order.location_status_verified, verified
    assert_not_includes Order.location_status_verified, unverified
    assert_includes Order.location_status_unverified, unverified
  end

  test "distance_meters and location_accuracy_meters are optional" do
    order = Order.new(valid_attributes)

    assert_nil order.distance_meters
    assert_nil order.location_accuracy_meters
    assert order.valid?
  end

  # --- Associations ---

  test "belongs to restaurant" do
    assert_equal restaurants(:osteria), orders(:pending_order).restaurant
  end

  test "belongs to customer" do
    assert_equal users(:customer), orders(:pending_order).customer
  end

  test "customer is optional for guest orders" do
    order = orders(:guest_order)
    assert_nil order.customer
    assert_equal "Jane Diner", order.guest_name
  end

  test "has many order_items" do
    assert_respond_to orders(:pending_order), :order_items
    assert_includes orders(:pending_order).order_items, order_items(:pending_barolo_glass)
  end

  test "destroys dependent order_items when deleted" do
    order = Order.create!(valid_attributes)
    order.order_items.create!(
      wine: wines(:barolo),
      glass_size_ml: 100,
      quantity: 1,
      unit_price_cents: 1800
    )
    assert_difference "OrderItem.count", -1 do
      order.destroy
    end
  end

  # --- Scopes ---

  test "recent scope orders by created_at descending" do
    older = Order.create!(valid_attributes.merge(created_at: 2.days.ago))
    newer = Order.create!(valid_attributes.merge(created_at: 1.day.ago))
    result = Order.recent.to_a
    assert result.index(newer) < result.index(older)
  end

  # The owner's poller compares the ids in this window against the ones it has
  # already announced, so the window has to be bounded, newest first, and the
  # same set for the same data every time it is asked. Every case below builds
  # on `enoteca`, which carries no order fixtures — the window is ordered by
  # created_at, and fixtures are all stamped at load time.
  def enoteca_order(created_at)
    Order.create!(valid_attributes.merge(restaurant: restaurants(:enoteca), created_at: created_at))
  end

  test "notification_window is bounded by NOTIFICATION_WINDOW" do
    (Order::NOTIFICATION_WINDOW + 2).times { |index| enoteca_order(index.minutes.ago) }

    assert_equal Order::NOTIFICATION_WINDOW,
      restaurants(:enoteca).orders.notification_window.count
  end

  test "notification_window returns the newest orders first" do
    older = enoteca_order(2.days.ago)
    newer = enoteca_order(1.minute.ago)

    assert_equal [ newer, older ], restaurants(:enoteca).orders.notification_window.to_a
  end

  # Two orders placed in the same instant would otherwise swap places between
  # two polls, and an order that comes back into the window is announced twice.
  test "notification_window breaks created_at ties on id" do
    stamp = 1.minute.ago
    pair = [ enoteca_order(stamp), enoteca_order(stamp) ]

    assert_equal pair.max_by(&:id), restaurants(:enoteca).orders.notification_window.first
  end

  # This scope runs on a timer for every owner page anyone has open, so it is
  # the one query in the app that must never fall back to sorting a restaurant's
  # whole order history. Only an index matching the ORDER BY — both columns,
  # both descending — turns it into a five-row walk.
  test "notification_window is backed by an index that matches its ordering" do
    index = ActiveRecord::Base.connection.indexes(:orders).find do |candidate|
      candidate.columns == %w[restaurant_id created_at id]
    end

    assert index, "no index covers Order.notification_window's filter and sort"
    # Postgres reports only the columns that depart from the default ascending.
    assert_equal({ "created_at" => :desc, "id" => :desc }, index.orders,
      "the index has to descend exactly as the scope does, or Postgres sorts anyway")
  end

  # --- calculate_total! ---

  test "calculate_total! sums order items" do
    order = orders(:pending_order)
    # pending_barolo_glass: quantity 2, unit_price_cents 1800 => 3600
    order.calculate_total!
    assert_equal 3600, order.reload.total_amount_cents
  end

  test "calculate_total! returns 0 for order with no items" do
    order = Order.create!(valid_attributes)
    order.calculate_total!
    assert_equal 0, order.reload.total_amount_cents
  end

  # --- approve! ---

  test "approve! changes status to approved" do
    order = orders(:pending_order)
    order.approve!
    assert order.reload.approved?
  end

  test "approve! does not move available_glasses" do
    order = orders(:pending_order)
    wine  = wines(:barolo)
    glasses_before = wine.available_glasses # 10
    order.approve!
    assert_equal glasses_before, wine.reload.available_glasses
  end

  test "approve! does nothing unless the order is pending" do
    order = orders(:approved_order)
    wine  = wines(:gavi)
    glasses_before = wine.available_glasses
    bottles_open_before = wine.wine_bottles.where(status: :open).count

    result = order.approve!

    assert_equal false, result
    assert order.reload.approved?
    assert_equal glasses_before, wine.reload.available_glasses
    assert_equal bottles_open_before, wine.wine_bottles.where(status: :open).count
  end

  test "approve! twice only opens one bottle and never moves stock" do
    order = orders(:pending_order)
    wine  = wines(:barolo)
    glasses_before = wine.available_glasses

    order.approve!
    second_result = order.approve!

    assert_equal false, second_result
    assert_equal glasses_before, wine.reload.available_glasses
    assert_equal 1, wine.wine_bottles.where(status: :open).count
  end

  test "approve! opens a sealed bottle when no open bottle exists" do
    # barolo has sealed_barolo (sealed) and no open bottle
    wine = wines(:barolo)
    assert_equal 0, wine.wine_bottles.where(status: :open).count

    order = orders(:pending_order)
    order.approve!

    assert_equal 1, wine.wine_bottles.where(status: :open).count
  end

  test "approve! does not open another bottle when one is already open" do
    # gavi already has open_gavi (open)
    wine = wines(:gavi)
    assert_equal 1, wine.wine_bottles.where(status: :open).count

    order = Order.create!(valid_attributes)
    order.order_items.create!(
      wine: wine,
      glass_size_ml: 100,
      quantity: 1,
      unit_price_cents: 900
    )
    order.approve!

    assert_equal 1, wine.wine_bottles.where(status: :open).count
  end

  # --- cancel! ---

  test "cancel! changes status to cancelled" do
    order = orders(:pending_order)
    order.cancel!
    assert order.reload.cancelled?
  end

  test "cancel! from pending restores glasses" do
    order = orders(:pending_order)
    wine  = wines(:barolo)
    glasses_before = wine.available_glasses
    order.cancel!
    # pending_barolo_glass: quantity 2
    assert_equal glasses_before + 2, wine.reload.available_glasses
  end

  test "cancel! from approved restores glasses" do
    order = orders(:approved_order)
    wine  = wines(:gavi)
    glasses_before = wine.available_glasses # 7
    order.cancel!
    # approved_gavi_glass: quantity 2
    assert_equal glasses_before + 2, wine.reload.available_glasses
  end

  test "cancel! twice restores once" do
    order = orders(:pending_order)
    wine  = wines(:barolo)
    glasses_before = wine.available_glasses

    order.cancel!
    second_result = order.cancel!

    assert_equal false, second_result
    assert_equal glasses_before + 2, wine.reload.available_glasses
  end

  # PlaceOrder locks wines in ascending id order when reserving (see
  # PlaceOrder#reserve_stock!). If cancel! released them in a different
  # order — order_items' own order, say — a cancel and a placement racing
  # over the same two wines could acquire their row locks in opposite
  # orders and deadlock in Postgres. This pins the release itself to
  # ascending wine_id, independent of the order the order_items were
  # created in, by inserting them in the reverse of wine-id order and
  # asserting the UPDATE statements against "wines" still fire lowest-id
  # first.
  test "cancel! releases wines in ascending wine_id order, not order_items order" do
    order = Order.create!(valid_attributes)
    lower_id_wine, higher_id_wine = [ wines(:barolo), wines(:gavi) ].sort_by(&:id)
    assert_operator lower_id_wine.id, :<, higher_id_wine.id

    # Created higher-id wine first, so order_items' own (creation) order is
    # the opposite of ascending wine_id — proves the release sorts
    # explicitly rather than happening to follow insertion order.
    order.order_items.create!(wine: higher_id_wine, glass_size_ml: 125, quantity: 1, unit_price_cents: 2200)
    order.order_items.create!(wine: lower_id_wine, glass_size_ml: 100, quantity: 1, unit_price_cents: 900)

    touched_wine_ids = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next unless payload[:name] == "Wine Update All"

      # increment!'s UPDATE binds "id" as its final parameter in the test
      # environment (prepared statements); fall back to an inlined literal
      # in case a different environment's adapter config inlines it instead.
      id_bind = payload[:binds]&.find { |bind| bind.name == "id" }
      touched_wine_ids << (id_bind ? id_bind.value : payload[:sql][/"wines"\."id" = (\d+)/, 1].to_i)
    end

    begin
      order.cancel!
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_equal [ lower_id_wine.id, higher_id_wine.id ], touched_wine_ids
  end

  test "cancel! from completed restores nothing" do
    order = Order.create!(valid_attributes.merge(status: :completed))
    wine  = wines(:barolo)
    order.order_items.create!(
      wine: wine,
      glass_size_ml: 100,
      quantity: 2,
      unit_price_cents: 1800
    )
    glasses_before = wine.available_glasses

    result = order.cancel!

    assert_equal false, result
    assert order.reload.completed?
    assert_equal glasses_before, wine.reload.available_glasses
  end

  # --- public_token ---

  test "generates a public_token automatically on create" do
    order = Order.create!(valid_attributes)
    assert order.public_token.present?
  end

  test "generates distinct public_tokens for different orders" do
    first = Order.create!(valid_attributes)
    second = Order.create!(valid_attributes)
    assert_not_equal first.public_token, second.public_token
  end
end
