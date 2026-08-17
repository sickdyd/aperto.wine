class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :wine

  enum :serving, { glass: 0, bottle: 1 }

  validates :glass_size_ml, inclusion: { in: Wine::GLASS_SIZES }, if: :glass?
  validates :glass_size_ml, absence: true, if: :bottle?
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than: 0 }

  def subtotal_cents
    unit_price_cents * quantity
  end
end
