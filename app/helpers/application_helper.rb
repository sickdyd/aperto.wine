module ApplicationHelper
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
