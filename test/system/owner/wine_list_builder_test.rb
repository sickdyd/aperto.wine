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
      within "[data-sortable-target='members']" do
        assert_text "Barolo Riserva"
      end

      # Persisted server-side: a reload still shows it on the list.
      visit_list(list)
      within "[data-sortable-target='members']" do
        assert_text "Barolo Riserva"
      end
      assert WineListItem.exists?(wine_list: list, wine: barolo)
    end

    test "owner removes a wine from the list with the delete button" do
      sign_in_as_owner
      list = wine_lists(:summer) # members: barolo, sold_out
      barolo = wines(:barolo)
      visit_list(list)

      accept_confirm do
        within "[data-id='#{wine_list_items(:summer_barolo).id}']" do
          find("button[type='submit']").click
        end
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

    # --- SECONDARY: drag-and-drop (SortableJS). These pass reliably under
    # headless Chrome; Minitest::Retry (2 retries) covers occasional infra
    # flake. The button-path tests above are the primary, must-pass coverage. ---

    test "owner drags an available wine onto the list" do
      sign_in_as_owner
      list = wine_lists(:winter)
      barolo = wines(:barolo)
      visit_list(list)

      source = find("[data-wine-id='#{barolo.id}']")
      target = find("[data-sortable-target='members']")
      source.drag_to(target)

      assert_text I18n.t("owner.wine_lists.members.added"), wait: 5
      assert WineListItem.exists?(wine_list: list, wine: barolo)
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
      assert_equal(
        [ soldout_item.id.to_s, barolo_item.id.to_s ],
        all("[data-sortable-target='members'] [data-id]").map { |el| el["data-id"] }
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
