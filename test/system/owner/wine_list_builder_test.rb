require "application_system_test_case"

module Owner
  class WineListBuilderTest < ApplicationSystemTestCase
    def sign_in_as_owner
      user = users(:owner)
      visit sign_in_path
      fill_in "email", with: user.email
      fill_in "password", with: "password123"
      find("input[type='submit']").click
      assert_text I18n.t("owner.restaurants.title"), wait: 5
    end

    def visit_list(wine_list)
      restaurant = restaurants(:osteria)
      visit edit_owner_restaurant_wine_list_path(restaurant_id: restaurant, id: wine_list)
      assert_text I18n.t("owner.wine_lists.members.title"), wait: 5
    end

    # Members are split into one drop container per wine colour, so member
    # selectors must name a colour to stay unambiguous.
    def members_selector(colour)
      "[data-sortable-target='members'][data-color='#{colour}']"
    end

    def red_members
      members_selector("red")
    end

    # --- PRIMARY: button path (keyboard / mobile accessible fallback) ---

    test "owner adds an available wine to the list with the Add button" do
      sign_in_as_owner
      list = wine_lists(:winter) # member: gavi; available: barolo, sold_out
      barolo = wines(:barolo)
      visit_list(list)

      within "[data-wine-id='#{barolo.id}']" do
        click_button I18n.t("owner.wine_lists.members.add_to_list")
      end

      assert_text I18n.t("owner.wine_lists.members.added"), wait: 5
      within red_members do
        assert_text "Barolo Riserva"
      end

      # Persisted server-side: a reload still shows it on the list.
      visit_list(list)
      within red_members do
        assert_text "Barolo Riserva"
      end
      assert WineListItem.exists?(wine_list: list, wine: barolo)
    end

    test "owner removes a wine from the list with the delete button" do
      sign_in_as_owner
      list = wine_lists(:summer) # members: barolo, sold_out
      barolo = wines(:barolo)
      visit_list(list)

      # Removing a wine is a one-click action: no confirmation dialog stands
      # between the owner and the delete button.
      assert_no_selector "[data-id='#{wine_list_items(:summer_barolo).id}'] " \
                         "button[type='submit'][data-turbo-confirm]"

      within "[data-id='#{wine_list_items(:summer_barolo).id}']" do
        find("button[type='submit']").click
      end

      assert_text I18n.t("owner.wine_lists.members.removed"), wait: 5
      assert_not WineListItem.exists?(wine_list: list, wine: barolo)
    end

    test "owner reorders a member with the position number field" do
      sign_in_as_owner
      list = wine_lists(:summer) # barolo pos 1, sold_out pos 2
      visit_list(list)

      within "[data-id='#{wine_list_items(:summer_barolo).id}']" do
        fill_in I18n.t("owner.wine_lists.members.position"), with: 5
        click_button I18n.t("shared.save")
      end

      assert_text I18n.t("owner.wine_lists.members.reordered"), wait: 5
      assert_equal 5, wine_list_items(:summer_barolo).reload.position
    end

    test "owner puts the whole cellar on a list with Add all wines" do
      sign_in_as_owner
      list = wine_lists(:winter) # member: gavi; the rest of osteria is available
      restaurant = restaurants(:osteria)
      visit_list(list)

      expected_added = restaurant.wines.where.not(id: list.wines.select(:id)).count

      click_button I18n.t("owner.wine_lists.members.add_all")

      assert_text I18n.t("owner.wine_lists.members.added_all", count: expected_added), wait: 5
      assert_equal restaurant.wines.count, list.reload.wines.count
      # Nothing left to add, so the button is gone on the repainted column.
      assert_no_button I18n.t("owner.wine_lists.members.add_all")
    end

    test "filtering the available wines column hides non-matching wines" do
      sign_in_as_owner
      list = wine_lists(:winter) # member: gavi; available: barolo, sold_out
      visit_list(list)

      within "[data-sortable-target='available']" do
        assert_text "Barolo Riserva"
        assert_text "Sold Out Wine"
      end

      fill_in I18n.t("owner.shared.filter.placeholder"), with: "Barolo"

      within "[data-sortable-target='available']" do
        assert_text "Barolo Riserva", wait: 5
        assert_no_text "Sold Out Wine"
      end
    end

    # --- SECONDARY: drag-and-drop (SortableJS). These pass reliably under
    # headless Chrome; Minitest::Retry (2 retries) covers occasional infra
    # flake. The button-path tests above are the primary, must-pass coverage. ---

    test "owner drags an available wine onto the list" do
      sign_in_as_owner
      list = wine_lists(:winter)
      barolo = wines(:barolo)
      visit_list(list)

      source = find("[data-wine-id='#{barolo.id}']")
      target = find(red_members) # barolo is red
      source.drag_to(target)

      assert_text I18n.t("owner.wine_lists.members.added"), wait: 5
      assert WineListItem.exists?(wine_list: list, wine: barolo)
    end

    test "dropping a wine on a colour group that isn't its own is rejected" do
      sign_in_as_owner
      list = wine_lists(:winter) # member: gavi (white); available includes barolo (red)
      barolo = wines(:barolo)
      visit_list(list)

      source = find("[data-wine-id='#{barolo.id}']")
      source.drag_to(find(members_selector("white")))

      # The put guard refuses the drop, so nothing is created. Give the failure
      # path the same budget a successful add would have had before asserting.
      assert_no_text I18n.t("owner.wine_lists.members.added"), wait: 2
      assert_not WineListItem.exists?(wine_list: list, wine: barolo)
      within members_selector("white") do
        assert_no_text "Barolo Riserva"
      end
    end

    test "owner drag-reorders members and the new order persists" do
      sign_in_as_owner
      list = wine_lists(:summer) # barolo pos 1, sold_out pos 2
      barolo_item = wine_list_items(:summer_barolo)
      soldout_item = wine_list_items(:summer_sold_out)
      visit_list(list)

      # The members list drags via an explicit handle, so the drag must start
      # there rather than on the whole row.
      handle = find("[data-id='#{barolo_item.id}'] [data-sortable-handle]")
      target = find("[data-id='#{soldout_item.id}']")
      handle.drag_to(target)

      # DOM reflects the new order immediately; wait for it before asserting.
      # Both wines are red, so the reorder happens inside the red group.
      assert_equal(
        [ soldout_item.id.to_s, barolo_item.id.to_s ],
        all("#{red_members} [data-id]").map { |el| el["data-id"] }
      )
      # onUpdate fires an async PATCH; poll until it persists.
      assert_reorder_persisted(barolo_item, soldout_item)
    end

    # The reorder PATCH is fired asynchronously by SortableJS's onUpdate; poll
    # the persisted positions within the Capybara wait budget instead of a
    # fixed sleep.
    def assert_reorder_persisted(later_item, earlier_item)
      deadline = Time.current + Capybara.default_max_wait_time
      loop do
        break if later_item.reload.position > earlier_item.reload.position
        raise Minitest::Assertion, "reorder did not persist" if Time.current > deadline
        sleep 0.1
      end
      assert_operator later_item.reload.position, :>, earlier_item.reload.position
    end
  end
end
