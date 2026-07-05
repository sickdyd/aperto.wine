class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :customer, class_name: "User"
  belongs_to :restaurant_table, optional: true
  has_many :order_items, dependent: :destroy

  enum :status, { pending: 0, approved: 1, cancelled: 2, completed: 3 }

  validates :total_amount_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }

  def calculate_total!
    update!(total_amount_cents: order_items.sum { |item| item.unit_price_cents * item.quantity })
  end

  def approve!
    transaction do
      update!(status: :approved)
      order_items.includes(:wine).each do |item|
        wine = item.wine
        wine.decrement!(:available_glasses, item.quantity)

        # Open a bottle if needed
        bottle = wine.wine_bottles.find_by(status: :sealed)
        bottle&.open! if wine.wine_bottles.where(status: :open).none?
      end
    end
  end

  def cancel!
    transaction do
      update!(status: :cancelled)
      # Restore glasses if order was previously approved
      if status_previously_was == "approved"
        order_items.each do |item|
          item.wine.increment!(:available_glasses, item.quantity)
        end
      end
    end
  end
end
