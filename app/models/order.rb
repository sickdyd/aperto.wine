class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :customer, class_name: "User", optional: true
  belongs_to :restaurant_table, optional: true
  has_many :order_items, dependent: :destroy

  has_secure_token :public_token

  enum :status, { pending: 0, approved: 1, cancelled: 2, completed: 3 }

  validates :total_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :guest_name, length: { maximum: 64 }

  scope :recent, -> { order(created_at: :desc) }

  def calculate_total!
    update!(total_amount_cents: order_items.sum { |item| item.unit_price_cents * item.quantity })
  end

  def approve!
    return false unless pending?

    transaction do
      update!(status: :approved)
      order_items.includes(:wine).each do |item|
        wine = item.wine

        # Open a bottle if needed
        bottle = wine.wine_bottles.find_by(status: :sealed)
        bottle&.open! if wine.wine_bottles.where(status: :open).none?
      end
    end
  end

  def cancel!
    return false unless pending? || approved?

    transaction do
      update!(status: :cancelled)
      # Release the reservation held since placement
      order_items.each do |item|
        item.wine.increment!(:available_glasses, item.quantity)
      end
    end
  end
end
