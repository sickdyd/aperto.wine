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

  test "requires customer" do
    order = Order.new(valid_attributes.merge(customer: nil))
    assert_not order.valid?
  end

  test "requires total_amount_cents >= 0" do
    order = Order.new(valid_attributes.merge(total_amount_cents: -1))
    assert_not order.valid?
    assert_includes order.errors[:total_amount_cents], "must be greater than or equal to 0"
  end

  test "allows total_amount_cents of zero" do
    order = Order.new(valid_attributes.merge(total_amount_cents: 0))
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

  # --- Associations ---

  test "belongs to restaurant" do
    assert_equal restaurants(:osteria), orders(:pending_order).restaurant
  end

  test "belongs to customer" do
    assert_equal users(:customer), orders(:pending_order).customer
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

  test "approve! decrements available_glasses for each item" do
    order = orders(:pending_order)
    wine  = wines(:barolo)
    glasses_before = wine.available_glasses # 10
    order.approve!
    # item quantity = 2
    assert_equal glasses_before - 2, wine.reload.available_glasses
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

  test "cancel! from pending does not restore glasses" do
    order = orders(:pending_order)
    wine  = wines(:barolo)
    glasses_before = wine.available_glasses
    order.cancel!
    assert_equal glasses_before, wine.reload.available_glasses
  end

  test "cancel! from approved restores glasses" do
    order = orders(:approved_order)
    wine  = wines(:gavi)
    glasses_before = wine.available_glasses # 7
    order.cancel!
    # approved_gavi_glass: quantity 2
    assert_equal glasses_before + 2, wine.reload.available_glasses
  end
end
