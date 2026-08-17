# Every open owner page asks Order.notification_window for a restaurant's five
# newest orders every fifteen seconds, which is
#
#   WHERE restaurant_id = ? ORDER BY created_at DESC, id DESC LIMIT 5
#
# index_orders_on_restaurant_id answers the filter but not the sort, so without
# this the busiest query in the app re-sorts every order a restaurant has ever
# taken, four times a minute, to return five rows. Matching the ORDER BY exactly
# — both columns, both descending — is what turns it into a five-row walk of the
# index with no sort at all.
#
# Built in the ordinary way rather than CONCURRENTLY: orders is small, so the
# write lock is measured in milliseconds, and a concurrent build that fails
# leaves an INVALID index behind for someone to find — a poor trade in a
# migration that runs as Render's preDeployCommand, where a clean failure simply
# halts the deploy with the previous version still serving.
class AddNotificationWindowIndexToOrders < ActiveRecord::Migration[8.1]
  def change
    add_index :orders, [ :restaurant_id, :created_at, :id ],
              order: { created_at: :desc, id: :desc },
              name: "index_orders_on_restaurant_id_and_recency"
  end
end
