# Records whether an order is actually *holding* a stock reservation, rather
# than inferring it from the status.
#
# Reservation moved from approval to placement in this deploy, so the two
# generations of order disagree about what a status implies. An order placed
# under the old code and still pending never had its glasses decremented — the
# old code did that at approve! — so releasing on cancel would invent glasses
# that were never taken. An order the old code already approved *did* take the
# decrement and must still release. Status alone cannot tell those apart; this
# flag can, and every order placed from here on sets it inside the same
# transaction as the reservation itself.
#
# Hence the backfill: `approved` rows are exactly the legacy orders that hold a
# decrement, and `pending` ones keep the false default so cancelling them
# releases nothing.
class AddStockReservedToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :stock_reserved, :boolean, null: false, default: false

    # Raw status value rather than the enum: a migration must keep meaning the
    # same thing after the model's enum is edited or the constant is gone.
    # 1 is Order.statuses[:approved].
    up_only do
      execute "UPDATE orders SET stock_reserved = TRUE WHERE status = 1"
    end
  end
end
