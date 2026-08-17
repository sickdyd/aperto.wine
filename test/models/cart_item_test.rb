require "test_helper"

class CartItemTest < ActiveSupport::TestCase
  test "exposes wine, serving, glass_size_ml and quantity" do
    item = CartItem.new(wine: wines(:gavi), serving: "glass", glass_size_ml: 125, quantity: 3)

    assert_equal wines(:gavi), item.wine
    assert_equal "glass", item.serving
    assert_equal 125, item.glass_size_ml
    assert_equal 3, item.quantity
  end

  test "unit_price_cents reads the wine's live bottle price for a bottle serving" do
    item = CartItem.new(wine: wines(:barolo), serving: "bottle", glass_size_ml: nil, quantity: 1)

    assert_equal wines(:barolo).price_bottle_cents, item.unit_price_cents
  end

  test "a bottle item's unit_price_cents reflects a price change on the underlying wine" do
    wine = wines(:barolo)
    item = CartItem.new(wine: wine, serving: "bottle", glass_size_ml: nil, quantity: 1)

    wine.update!(price_bottle_cents: 9999)

    assert_equal 9999, item.unit_price_cents
  end

  test "unit_price_cents reads the wine's live price for the glass size" do
    item = CartItem.new(wine: wines(:gavi), serving: "glass", glass_size_ml: 125, quantity: 1)

    assert_equal wines(:gavi).price_for_glass(125), item.unit_price_cents
  end

  test "unit_price_cents reflects a price change on the underlying wine" do
    wine = wines(:gavi)
    item = CartItem.new(wine: wine, serving: "glass", glass_size_ml: 125, quantity: 1)

    wine.update!(price_125ml_cents: 1234)

    assert_equal 1234, item.unit_price_cents
  end

  test "subtotal_cents multiplies unit price by quantity" do
    item = CartItem.new(wine: wines(:gavi), serving: "glass", glass_size_ml: 125, quantity: 3)

    assert_equal wines(:gavi).price_for_glass(125) * 3, item.subtotal_cents
  end
end
