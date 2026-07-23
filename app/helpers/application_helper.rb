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
end
