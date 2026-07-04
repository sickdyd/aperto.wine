require "test_helper"

module Owner
  class NavigationHelperTest < ActionView::TestCase
    attr_accessor :controller_name, :action_name

    test "active when controller matches and no actions given" do
      self.controller_name = "orders"
      self.action_name = "index"

      assert owner_nav_active?("orders")
      assert_not owner_nav_active?("wines")
    end

    test "active when controller is in the given list" do
      self.controller_name = "wine_list_items"
      self.action_name = "create"

      assert owner_nav_active?(%w[wine_lists wine_list_items wines])
    end

    test "action list restricts the match" do
      self.controller_name = "restaurants"
      self.action_name = "edit"

      assert owner_nav_active?("restaurants", actions: %w[edit update])
      assert_not owner_nav_active?("restaurants", actions: "show")
    end

    test "link attrs mark the active page for assistive tech" do
      assert_equal({ class: "menu-active", "aria-current": "page" }, owner_nav_link_attrs(true))
      assert_equal({ class: nil, "aria-current": nil }, owner_nav_link_attrs(false))
    end
  end
end
