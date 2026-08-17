require "application_system_test_case"

module Owner
  class WinesSearchTest < ApplicationSystemTestCase
    def sign_in_as_owner
      user = users(:owner)
      visit sign_in_path
      fill_in "email", with: user.email
      fill_in "password", with: "password123"
      find("input[type='submit']").click
      assert_text I18n.t("owner.restaurants.title"), wait: 5
    end

    def visit_wines
      restaurant = restaurants(:osteria)
      visit owner_restaurant_wines_path(restaurant_id: restaurant)
      assert_text I18n.t("owner.wines.title"), wait: 5
    end

    # The colour group headings are set in caps by CSS (`text-transform`), so
    # the rendered text is "RED" while the translation is "Red". Match the word
    # case-insensitively rather than asserting on the styling.
    def color_heading(color)
      /\b#{Regexp.escape(I18n.t("owner.wines.colors.#{color}"))}\b/i
    end

    test "typing a wine name filters the list and clearing restores it" do
      sign_in_as_owner
      visit_wines

      assert_text "Barolo Riserva"
      assert_text "Gavi di Gavi"

      fill_in I18n.t("owner.shared.filter.placeholder"), with: "Barolo"

      assert_text "Barolo Riserva", wait: 5
      assert_no_text "Gavi di Gavi"

      fill_in I18n.t("owner.shared.filter.placeholder"), with: ""

      assert_text "Barolo Riserva", wait: 5
      assert_text "Gavi di Gavi"
    end

    test "shows an empty state when nothing matches" do
      sign_in_as_owner
      visit_wines

      fill_in I18n.t("owner.shared.filter.placeholder"), with: "nonexistent wine xyz"

      assert_text I18n.t("owner.shared.filter.no_results"), wait: 5
      assert_no_text "Barolo Riserva"
      assert_no_text "Gavi di Gavi"
      assert_no_text "Sold Out Wine"
    end

    test "a color group hides entirely once all its wines are filtered out" do
      sign_in_as_owner
      visit_wines

      assert_text color_heading(:red), wait: 5
      assert_text color_heading(:white), wait: 5

      fill_in I18n.t("owner.shared.filter.placeholder"), with: "Barolo"

      # Gavi di Gavi is the only white wine, so the whole "White" group
      # (heading included) disappears once it is filtered out. The "Red"
      # group stays visible because Barolo Riserva still matches.
      assert_text color_heading(:red), wait: 5
      assert_no_text color_heading(:white)
    end

    # list_filter_controller.js is shared with the public menu, which renders
    # a "facet" chip target this page never does. This guards that the
    # controller's facet-matching stays a no-op with none present, so a
    # future change to the shared facet logic can't silently break text-only
    # filtering here without this test explaining why it mattered.
    test "text filtering still works on a page with no facet chips (shared list_filter_controller regression)" do
      sign_in_as_owner
      visit_wines

      assert_no_selector "[data-list-filter-target~='facet']"

      fill_in I18n.t("owner.shared.filter.placeholder"), with: "Barolo"

      assert_text "Barolo Riserva", wait: 5
      assert_no_text "Gavi di Gavi"
    end
  end
end
