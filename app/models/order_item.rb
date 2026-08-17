class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :wine

  # Values (and their integer positions) are derived from Wine::SERVINGS —
  # the same constant Cart#add validates a requested serving against — so
  # the cart's vocabulary and this column's enum can never drift apart.
  # Derived from an index, so Wine::SERVINGS may only ever grow by
  # appending: reordering or removing an entry renumbers or orphans
  # existing rows.
  #
  # The DB check constraint `order_items_serving_glass_size` (see
  # db/migrate/20260817000001_add_serving_to_order_items.rb) is coupled to
  # this enum but not derived from it: it is an OR of exactly the two
  # conjunctions for serving 0 and 1, so it rejects — loudly, as a
  # CheckViolation, not silently — any row for a third serving value. Adding
  # a third entry to Wine::SERVINGS requires a follow-up migration to widen
  # that constraint before this enum can actually use it.
  enum :serving, Wine::SERVINGS.each_with_index.to_h

  validates :glass_size_ml, inclusion: { in: Wine::GLASS_SIZES }, if: :glass?
  validates :glass_size_ml, absence: true, if: :bottle?
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than: 0 }

  def subtotal_cents
    unit_price_cents * quantity
  end
end
