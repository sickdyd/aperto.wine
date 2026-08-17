require "test_helper"

class CartItemTest < ActiveSupport::TestCase
  test "exposes wine, glass_size_ml and quantity" do
    item = CartItem.new(wine: wines(:gavi), glass_size_ml: 125, quantity: 3)

    assert_equal wines(:gavi), item.wine
    assert_equal 125, item.glass_size_ml
    assert_equal 3, item.quantity
  end

  test "unit_price_cents reads the wine's live price for the glass size" do
    item = CartItem.new(wine: wines(:gavi), glass_size_ml: 125, quantity: 1)

    assert_equal wines(:gavi).price_for_glass(125), item.unit_price_cents
  end

  test "unit_price_cents reflects a price change on the underlying wine" do
    wine = wines(:gavi)
    item = CartItem.new(wine: wine, glass_size_ml: 125, quantity: 1)

    wine.update!(price_125ml_cents: 1234)

    assert_equal 1234, item.unit_price_cents
  end

  test "subtotal_cents multiplies unit price by quantity" do
    item = CartItem.new(wine: wines(:gavi), glass_size_ml: 125, quantity: 3)

    assert_equal wines(:gavi).price_for_glass(125) * 3, item.subtotal_cents
  end

  # --- exceeds_stock? ---

  test "exceeds_stock? is false when quantity is within the wine's available_glasses" do
    item = CartItem.new(wine: wines(:gavi), glass_size_ml: 125, quantity: 7)

    assert_not item.exceeds_stock?
  end

  test "exceeds_stock? is true when quantity exceeds the wine's available_glasses" do
    item = CartItem.new(wine: wines(:gavi), glass_size_ml: 125, quantity: 8)

    assert item.exceeds_stock?
  end

  test "exceeds_stock? reflects a stock change on the underlying wine" do
    wine = wines(:gavi)
    item = CartItem.new(wine: wine, glass_size_ml: 125, quantity: 7)
    assert_not item.exceeds_stock?

    wine.update!(available_glasses: 3)

    assert item.exceeds_stock?
  end
end
