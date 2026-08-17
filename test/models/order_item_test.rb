require "test_helper"

class OrderItemTest < ActiveSupport::TestCase
  def valid_attributes
    {
      order: orders(:pending_order),
      wine: wines(:barolo),
      glass_size_ml: 100,
      quantity: 1,
      unit_price_cents: 1800
    }
  end

  # --- Validations ---

  test "creates a valid order item" do
    item = OrderItem.new(valid_attributes)
    assert item.valid?
  end

  test "requires order" do
    item = OrderItem.new(valid_attributes.merge(order: nil))
    assert_not item.valid?
  end

  test "requires wine" do
    item = OrderItem.new(valid_attributes.merge(wine: nil))
    assert_not item.valid?
  end

  test "glass_size_ml must be in GLASS_SIZES" do
    item = OrderItem.new(valid_attributes.merge(glass_size_ml: 200))
    assert_not item.valid?
    assert item.errors.of_kind?(:glass_size_ml, :inclusion)
  end

  test "accepts all valid glass sizes" do
    Wine::GLASS_SIZES.each do |size|
      item = OrderItem.new(valid_attributes.merge(glass_size_ml: size))
      assert item.valid?, "Expected glass size #{size} to be valid"
    end
  end

  test "glass serving with nil glass_size_ml is invalid" do
    item = OrderItem.new(valid_attributes.merge(serving: :glass, glass_size_ml: nil))
    assert_not item.valid?
    assert item.errors.of_kind?(:glass_size_ml, :inclusion)
  end

  test "bottle serving with nil glass_size_ml is valid" do
    item = OrderItem.new(valid_attributes.merge(serving: :bottle, glass_size_ml: nil))
    assert item.valid?
  end

  test "bottle serving with a glass_size_ml present is invalid" do
    item = OrderItem.new(valid_attributes.merge(serving: :bottle, glass_size_ml: 100))
    assert_not item.valid?
    assert item.errors.of_kind?(:glass_size_ml, :present)
  end

  # --- serving enum ---

  test "serving enum values" do
    assert_equal 0, OrderItem.servings[:glass]
    assert_equal 1, OrderItem.servings[:bottle]
  end

  test "serving defaults to glass" do
    item = OrderItem.new(valid_attributes)
    assert item.glass?
  end

  # --- DB check constraint ---
  # The Ruby validations above are mirrored by a DB check constraint so an
  # inconsistent row can't be persisted by a path that bypasses validations
  # (bulk update, raw SQL). Insert around the model validations and assert
  # the database itself rejects it.

  test "database rejects a glass row with no glass_size_ml, bypassing validations" do
    item = OrderItem.create!(valid_attributes)
    assert_raises(ActiveRecord::StatementInvalid) do
      item.update_column(:glass_size_ml, nil)
    end
  end

  test "database rejects a bottle row with a glass_size_ml, bypassing validations" do
    item = OrderItem.create!(valid_attributes.merge(serving: :bottle, glass_size_ml: nil))
    assert_raises(ActiveRecord::StatementInvalid) do
      item.update_column(:glass_size_ml, 100)
    end
  end

  test "requires quantity greater than 0" do
    item = OrderItem.new(valid_attributes.merge(quantity: 0))
    assert_not item.valid?
    assert item.errors.of_kind?(:quantity, :greater_than)
  end

  test "rejects negative quantity" do
    item = OrderItem.new(valid_attributes.merge(quantity: -1))
    assert_not item.valid?
  end

  test "requires unit_price_cents greater than 0" do
    item = OrderItem.new(valid_attributes.merge(unit_price_cents: 0))
    assert_not item.valid?
    assert item.errors.of_kind?(:unit_price_cents, :greater_than)
  end

  test "rejects negative unit_price_cents" do
    item = OrderItem.new(valid_attributes.merge(unit_price_cents: -100))
    assert_not item.valid?
  end

  # --- subtotal_cents ---

  test "subtotal_cents returns unit_price_cents * quantity" do
    item = OrderItem.new(valid_attributes.merge(unit_price_cents: 1800, quantity: 3))
    assert_equal 5400, item.subtotal_cents
  end

  test "subtotal_cents returns unit_price_cents when quantity is 1" do
    item = OrderItem.new(valid_attributes.merge(unit_price_cents: 900, quantity: 1))
    assert_equal 900, item.subtotal_cents
  end

  test "subtotal_cents is correct for fixture item" do
    item = order_items(:pending_barolo_glass)
    # quantity: 2, unit_price_cents: 1800
    assert_equal 3600, item.subtotal_cents
  end

  # --- Associations ---

  test "belongs to order" do
    assert_equal orders(:pending_order), order_items(:pending_barolo_glass).order
  end

  test "belongs to wine" do
    assert_equal wines(:barolo), order_items(:pending_barolo_glass).wine
  end
end
