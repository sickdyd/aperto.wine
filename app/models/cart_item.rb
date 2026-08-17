# A value object pairing a live Wine with the glass size and quantity a
# diner chose. Holds no session and performs no queries — Cart is
# responsible for loading the Wine and deciding whether a line still
# qualifies to become a CartItem (see Cart#items).
class CartItem
  attr_reader :wine, :glass_size_ml, :quantity

  def initialize(wine:, glass_size_ml:, quantity:)
    @wine = wine
    @glass_size_ml = glass_size_ml
    @quantity = quantity
  end

  # Always re-read from the wine, never from the session — a tampered
  # cookie cannot dictate a price this way.
  def unit_price_cents
    wine.price_for_glass(glass_size_ml)
  end

  def subtotal_cents
    unit_price_cents * quantity
  end
end
