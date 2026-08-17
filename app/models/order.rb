class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :customer, class_name: "User", optional: true
  belongs_to :restaurant_table, optional: true
  has_many :order_items, dependent: :destroy

  has_secure_token :public_token

  enum :status, { pending: 0, approved: 1, cancelled: 2, completed: 3 }

  # What the geofence was able to conclude about where this order was placed
  # from. Prefixed on purpose: `status` above already owns the unprefixed
  # namespace, and a bare `verified?` or `Order.verified` sitting beside
  # `approved?` would read as a claim about the order's own state.
  #
  # - not_checked — no claim was made: the restaurant has the geofence off, or
  #   has no coordinates to measure from. It is the column default, so every
  #   order placed before this feature keeps it and no owner is shown a badge
  #   implying a check that never ran.
  # - verified — a usable position fix was supplied and it was within range.
  # - unverified — the diner refused permission, the position was unavailable
  #   or timed out, or the fix was too imprecise to judge either way. The order
  #   is still accepted (turning these away would cost real orders over a
  #   browser prompt) but the owner sees that nothing was confirmed.
  #
  # There is deliberately no out_of_range member: a placement outside the radius
  # is rejected, so no row ever exists to carry that state.
  enum :location_status, { not_checked: 0, verified: 1, unverified: 2 }, prefix: true

  validates :total_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :guest_name, length: { maximum: 64 }

  # How many of the newest orders the owner's dashboard holds in view at once.
  # It bounds two things at the same number on purpose: how many toasts a
  # single poll can raise onto a screen that has room for a handful, and how
  # many ids the browser sends back as "already announced". A larger window
  # would only ever announce orders the owner is about to see on the board
  # anyway; a smaller one would let a burst slip past unannounced.
  NOTIFICATION_WINDOW = 5

  scope :recent, -> { order(created_at: :desc) }

  # The newest orders, in a fixed order. The id tiebreak is load-bearing rather
  # than tidiness: two orders placed in the same instant would otherwise be free
  # to swap places between one poll and the next, and an order that drops out of
  # the window and comes back is an order announced twice.
  scope :notification_window, -> { order(created_at: :desc, id: :desc).limit(NOTIFICATION_WINDOW) }

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
