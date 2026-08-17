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

  # The status guards below both read `self`'s status *after* `lock!`, never
  # before. That ordering is the whole point: the in-memory attribute was
  # loaded by the controller before this transaction opened, so two concurrent
  # requests over the same order (two staff tabs, a Turbo retry) would both
  # find it `pending` and both run the body — releasing the same reservation
  # twice, or approving an order that no longer holds one. `lock!` reloads
  # under `SELECT ... FOR UPDATE`, so the second caller reads what the first
  # committed and falls out at the guard.
  #
  # The lock is on the `orders` row, which no placement ever takes (PlaceOrder
  # locks `wines`), so it introduces no lock-ordering risk of its own.
  #
  # Both return true when they did the work and false when the guard turned
  # them away — Owner::OrdersController tells the owner which happened.
  def approve!
    transaction do
      lock!
      next false unless pending?

      update!(status: :approved)
      order_items.includes(:wine).each do |item|
        wine = item.wine

        # Open a bottle if needed
        bottle = wine.wine_bottles.find_by(status: :sealed)
        bottle&.open! if wine.wine_bottles.where(status: :open).none?
      end
      true
    end
  end

  def cancel!
    transaction do
      lock!
      next false unless pending? || approved?

      # Release only what this order actually holds. Orders placed before
      # reservation moved to placement never took a decrement while pending
      # (the old code took it at approve!), so an unconditional release would
      # invent glasses on their first cancel — see the stock_reserved
      # migration. Clearing the flag in the same UPDATE as the status means a
      # second release is impossible even if the lock above were ever lost.
      release = stock_reserved?
      update!(status: :cancelled, stock_reserved: false)
      next true unless release

      # Glass lines only, exactly mirroring what PlaceOrder#reserve_stock!
      # spent. A bottle line took no decrement — there is no bottle stock
      # column, a positive bottle price being the whole of what "bottle
      # available" means (Wine#bottle_available?) — so releasing against one
      # would invent glasses out of nothing, and a bottle-only order would
      # mint a glass per bottle on every cancel.
      #
      # Ordered by wine_id so two cancels racing over two orders that share
      # the same pair of wines take their row locks in the same sequence and
      # cannot deadlock each other. (A cancel cannot deadlock against a
      # placement: placement takes every wine lock it needs and then waits on
      # nothing a cancel holds.)
      order_items.glass.includes(:wine).order(:wine_id).each do |item|
        item.wine.increment!(:available_glasses, item.quantity)
      end
      true
    end
  end
end
