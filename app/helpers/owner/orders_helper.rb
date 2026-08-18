module Owner
  module OrdersHelper
    # The two live copies of the tally: the sidebar's, and the one in the mobile
    # top bar — the only one a phone shows without opening the drawer. Named
    # here rather than at each call site because the poller has to address the
    # very same ids from a Turbo Stream, and a badge whose id drifted would go
    # quietly stale instead of failing.
    BADGE_IDS = { sidebar: "owner-orders-badge", mobile: "owner-orders-badge-mobile" }.freeze

    # The order-sound control, and there is only one of it: it lives on the
    # restaurant settings page (owner/restaurants/edit), not in the chrome. The
    # badge is a reading — it has to be visible from wherever you are, hence a
    # pair. This is a preference, set once per device and then left alone, so it
    # belongs with the other settings rather than in the column you navigate by.
    #
    # Nothing about the chime depends on this element existing: the controller
    # is mounted on the shell and announces on every owner page, including all
    # the ones that no longer carry a control. Named here anyway, because the
    # system tests address the id the settings page renders.
    SOUND_TOGGLE_ID = "owner-order-sound"

    # The tally on the Orders entry: what is still waiting on the owner, not how
    # much has been sold. Re-read on every owner page render and restated by the
    # poller, so a badge is never older than one poll.
    #
    # Memoised because the answer is asked for once per badge and every page
    # carries two of them — one count query, not two, and the pair can never
    # disagree with each other on the same render.
    def owner_pending_orders_count(restaurant)
      @owner_pending_orders_counts ||= {}
      @owner_pending_orders_counts[restaurant.id] ||= restaurant.orders.pending.count
    end

    # The seed the poller starts from. Everything already on the page counts as
    # announced — without this the first poll after every navigation would toast
    # the last few orders all over again.
    def owner_recent_order_ids(restaurant)
      restaurant.orders.notification_window.pluck(:id)
    end
  end
end
