module Owner
  module OrdersHelper
    # The two live copies of the tally: the sidebar's, and the one in the mobile
    # top bar — the only one a phone shows without opening the drawer. Named
    # here rather than at each call site because the poller has to address the
    # very same ids from a Turbo Stream, and a badge whose id drifted would go
    # quietly stale instead of failing.
    BADGE_IDS = { sidebar: "owner-orders-badge", mobile: "owner-orders-badge-mobile" }.freeze

    # The tally on the sidebar's Orders entry: what is still waiting on the
    # owner, not how much has been sold. Re-read on every owner page render and
    # restated by the poller, so a badge is never older than one poll.
    def owner_pending_orders_count(restaurant)
      restaurant.orders.pending.count
    end

    # The seed the poller starts from. Everything already on the page counts as
    # announced — without this the first poll after every navigation would toast
    # the last few orders all over again.
    def owner_recent_order_ids(restaurant)
      restaurant.orders.notification_window.pluck(:id)
    end
  end
end
