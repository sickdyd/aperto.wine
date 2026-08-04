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
  def order_customer_label(order)
    order.customer&.name || order.guest_name.presence || t("owner.orders.guest")
  end
end
