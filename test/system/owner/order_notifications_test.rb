require "application_system_test_case"

# The whole point of the feature, in a real browser: an order placed while the
# owner is looking at some other page of the dashboard has to announce itself
# without the owner reloading anything.
#
# Every case here places the order straight through the model rather than by
# driving a second browser session — system tests share one connection with the
# app server, so a record written here is a record the next poll sees, and the
# diner's side of this journey is already covered by wine_ordering_test.
module Owner
  class OrderNotificationsTest < ApplicationSystemTestCase
    setup do
      @restaurant = restaurants(:osteria)
    end

    def sign_in_as_owner
      user = users(:owner)
      visit sign_in_path
      fill_in "email", with: user.email
      fill_in "password", with: "password123"
      find("input[type='submit']").click
      assert_text I18n.t("owner.restaurants.title"), wait: 5
    end

    # The wines page: somewhere inside the restaurant, and not the orders board
    # itself, so what is asserted is genuinely the ambient notification.
    def visit_dashboard
      visit owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_text I18n.t("owner.wines.title"), wait: 5
    end

    def place_order(table: restaurant_tables(:sala_t1))
      Order.create!(
        restaurant: @restaurant, restaurant_table: table,
        status: :pending, total_amount_cents: 2400
      )
    end

    test "an order placed while the owner is elsewhere raises a toast" do
      sign_in_as_owner
      visit_dashboard

      order = place_order

      # Case-insensitive: the band's label is set in mono caps by the stylesheet.
      assert_selector ".toast-band", text: /#{Regexp.escape(I18n.t("owner.orders.new_order"))}/i, wait: 10
      assert_selector ".toast-band", text: "##{order.id}"
      assert_selector ".toast-band", text: restaurant_tables(:sala_t1).name
    end

    test "the toast leads to the order it announced" do
      sign_in_as_owner
      visit_dashboard
      order = place_order

      assert_selector ".toast-band", text: "##{order.id}", wait: 10
      find(".toast-band a").click

      assert_current_path owner_restaurant_order_path(restaurant_id: @restaurant, id: order)
    end

    test "the sidebar badge counts the orders still waiting and moves as they arrive" do
      sign_in_as_owner
      visit_dashboard

      before = find("#owner-orders-badge", visible: :all)["data-pending-count"].to_i
      place_order

      Owner::OrdersHelper::BADGE_IDS.each_value do |badge_id|
        assert_selector "##{badge_id}[data-pending-count='#{before + 1}']", visible: :all, wait: 10
        assert_selector "##{badge_id}", text: (before + 1).to_s, visible: :all
      end
    end

    # A toast is only news the first time. The poller runs every second under
    # test, so a second copy would show up well inside this wait.
    test "the same order is never announced twice" do
      sign_in_as_owner
      visit_dashboard
      order = place_order

      assert_selector ".toast-band", text: "##{order.id}", wait: 10

      # Waits out several more polls for a second copy that must never come.
      assert_not page.has_selector?(".toast-band", count: 2, wait: 3),
        "the poller announced an order it had already announced"
    end

    test "orders placed at another of the owner's restaurants stay there" do
      sign_in_as_owner
      visit_dashboard

      Order.create!(restaurant: restaurants(:enoteca), status: :pending, total_amount_cents: 500)

      assert_no_selector ".toast-band", wait: 3
    end
  end
end
