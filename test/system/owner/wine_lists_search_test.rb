require "application_system_test_case"

module Owner
  class WineListsSearchTest < ApplicationSystemTestCase
    def sign_in_as_owner
      user = users(:owner)
      visit sign_in_path
      fill_in "email", with: user.email
      fill_in "password", with: "password123"
      find("input[type='submit']").click
      assert_text I18n.t("owner.restaurants.title"), wait: 5
    end

    def visit_wine_lists
      restaurant = restaurants(:osteria)
      visit owner_restaurant_wine_lists_path(restaurant_id: restaurant)
      assert_text I18n.t("owner.wine_lists.title"), wait: 5
    end

    test "typing a list name filters the list and clearing restores it" do
      sign_in_as_owner
      visit_wine_lists

      assert_text "Summer Selection"
      assert_text "Winter Selection"

      fill_in I18n.t("owner.shared.filter.placeholder"), with: "summer"

      assert_text "Summer Selection", wait: 5
      assert_no_text "Winter Selection"

      fill_in I18n.t("owner.shared.filter.placeholder"), with: ""

      assert_text "Summer Selection", wait: 5
      assert_text "Winter Selection"
    end

    test "shows an empty state when no list matches" do
      sign_in_as_owner
      visit_wine_lists

      fill_in I18n.t("owner.shared.filter.placeholder"), with: "nonexistent list xyz"

      assert_text I18n.t("owner.shared.filter.no_results"), wait: 5
      assert_no_text "Summer Selection"
      assert_no_text "Winter Selection"
    end
  end
end
