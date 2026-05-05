module ApplicationHelper
  def wine_color_class(color)
    case color.to_s
    when "red" then "bg-red-800"
    when "white" then "bg-amber-200"
    when "rose" then "bg-pink-300"
    when "sparkling" then "bg-yellow-100 border border-yellow-300"
    when "dessert" then "bg-amber-500"
    else "bg-base-300"
    end
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
end
