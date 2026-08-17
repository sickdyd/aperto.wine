require "test_helper"

module Owner
  class OrdersHelperTest < ActionView::TestCase
    setup do
      # enoteca carries no order fixtures, so each case here counts only what
      # it created itself.
      @restaurant = restaurants(:enoteca)
    end

    def place_order(status: :pending)
      Order.create!(restaurant: @restaurant, status: status, total_amount_cents: 900)
    end

    test "the pending tally counts only orders still awaiting the owner" do
      2.times { place_order }
      place_order(status: :approved)
      place_order(status: :cancelled)

      assert_equal 2, owner_pending_orders_count(@restaurant)
    end

    test "the pending tally is zero when nothing is waiting" do
      assert_equal 0, owner_pending_orders_count(@restaurant)
    end

    # The seed the poller starts from: everything already on the page has been
    # seen, so none of it may be announced as new on the first poll.
    test "the seeded window is the ids the page was rendered with" do
      orders = 2.times.map { place_order }

      assert_equal orders.map(&:id).sort, owner_recent_order_ids(@restaurant).sort
    end

    test "the seeded window is bounded like the model's own" do
      (Order::NOTIFICATION_WINDOW + 2).times { place_order }

      assert_equal Order::NOTIFICATION_WINDOW, owner_recent_order_ids(@restaurant).size
    end

    test "the seeded window is empty for a restaurant with no orders" do
      assert_empty owner_recent_order_ids(@restaurant)
    end
  end
end
