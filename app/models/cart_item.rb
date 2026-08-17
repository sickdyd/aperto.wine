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

  # True once the quantity already sitting in the cart outruns what is
  # actually left — can happen without the diner doing anything, e.g. stock
  # falling under a line already added. A sold-out wine never reaches this
  # check as a CartItem at all: Wine#available? is false at 0
  # available_glasses, so Cart drops the line as :wine_unavailable before a
  # CartItem for it is ever built (see Cart#drop_reason).
  def exceeds_stock?
    quantity > wine.available_glasses
  end
end
