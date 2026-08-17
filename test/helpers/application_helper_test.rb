require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "order_customer_label returns the customer's name when present" do
    order = orders(:pending_order)
    assert_equal order.customer.name, order_customer_label(order)
  end

  test "order_customer_label falls back to guest_name when there is no customer" do
    order = orders(:guest_order)
    assert_equal "Jane Diner", order_customer_label(order)
  end

  # The "Guest" fallback lives under the shared namespace, not owner.orders
  # (final review finding 6) — orders/show.html.erb is a customer-facing
  # page and must not reach into an owner-only locale key.
  test "order_customer_label falls back to a translated Guest label when both are absent" do
    order = orders(:guest_order)
    order.guest_name = nil
    assert_equal I18n.t("shared.guest"), order_customer_label(order)
  end

  # A quarter-minute is the production cadence; the suite cannot afford to wait
  # that long for a toast, and Capybara's default wait is shorter still.
  test "the owner poll runs far more often under test than in production" do
    assert_operator order_notifications_poll_interval_ms, :<,
      ApplicationHelper::ORDER_NOTIFICATIONS_POLL_INTERVAL_MS,
      "a system test asserting on a live notification would time out before " \
      "the first poll ever fired"
  end
end
