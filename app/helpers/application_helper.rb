module ApplicationHelper
  # Long enough to read a sentence twice, short enough that a stale toast is
  # not still floating over the next page.
  FLASH_TOAST_TIMEOUT_MS = 6_000

  # How long a floating flash band waits before dismissing itself, in
  # milliseconds; 0 means "never, wait for the close button".
  #
  # Zero under test is deliberate: a band that removes itself on a timer races
  # every system test that asserts on flash copy, and the failure looks like a
  # flake rather than like a timeout.
  def flash_toast_timeout_ms
    Rails.env.test? ? 0 : FLASH_TOAST_TIMEOUT_MS
  end

  # How often an open owner page asks whether an order has arrived. Fifteen
  # seconds is well inside the time it takes anyone to walk to a table, and it
  # is one small request per open tab — cheap enough that it needs no cleverness
  # about backing off, and the poller stops entirely while the tab is hidden.
  ORDER_NOTIFICATIONS_POLL_INTERVAL_MS = 15_000

  # A second under test, for the same reason the flash timeout is zero: a
  # browser test that has to sit out the production cadence before the thing it
  # is asserting on can possibly appear is a test that only ever times out.
  ORDER_NOTIFICATIONS_TEST_POLL_INTERVAL_MS = 1_000

  def order_notifications_poll_interval_ms
    Rails.env.test? ? ORDER_NOTIFICATIONS_TEST_POLL_INTERVAL_MS : ORDER_NOTIFICATIONS_POLL_INTERVAL_MS
  end

  def format_cents(cents)
    return nil unless cents&.positive?

    number_to_currency(cents / 100.0, unit: "\u20AC", format: "%u%n")
  end

  def order_status_badge_class(status)
    case status.to_s
    when "pending" then "badge-warning"
    when "approved" then "badge-success"
    when "cancelled" then "badge-error"
    when "completed" then "badge-info"
    else "badge-ghost"
    end
  end

  # Customer name, else guest name, else a translated "Guest" fallback —
  # orders may belong to a signed-in customer or an unauthenticated guest.
  # Shared with orders/show.html.erb, a customer-facing page, so the
  # fallback lives under the top-level shared namespace rather than
  # owner.orders — reading an owner-only key from a diner-facing page was
  # the bug (final review finding 6).
  def order_customer_label(order)
    order.customer&.name || order.guest_name.presence || t("shared.guest")
  end
end
