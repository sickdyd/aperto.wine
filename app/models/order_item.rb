class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :wine

  validates :glass_size_ml, inclusion: { in: Wine::GLASS_SIZES }
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than: 0 }

  def subtotal_cents
    unit_price_cents * quantity
  end
end
