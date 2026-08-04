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

  test "order_customer_label falls back to a translated Guest label when both are absent" do
    order = orders(:guest_order)
    order.guest_name = nil
    assert_equal I18n.t("owner.orders.guest"), order_customer_label(order)
  end
end
