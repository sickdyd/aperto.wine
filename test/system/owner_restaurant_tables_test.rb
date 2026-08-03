require "application_system_test_case"

class OwnerRestaurantTablesTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text I18n.t("owner.restaurants.title"), wait: 5
  end

  test "owner can create a table and open its QR code" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit owner_restaurant_tables_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.tables.title"), wait: 5
    # Area headings are CSS-uppercased, so match case-insensitively.
    assert_text(/sala principale/i)

    click_link I18n.t("owner.tables.add"), match: :first
    assert_text I18n.t("owner.tables.new_title"), wait: 5

    fill_in I18n.t("owner.tables.form.name"), with: "Tavolo 30"
    fill_in I18n.t("owner.tables.form.area"), with: "Terrazza"
    find("input[type='submit']").click

    assert_text I18n.t("owner.tables.created"), wait: 5
    assert_text "Tavolo 30"
    assert_text(/terrazza/i)

    # Open the new table's QR page
    new_table = RestaurantTable.find_by!(name: "Tavolo 30")
    visit qr_owner_restaurant_table_path(restaurant_id: restaurant, id: new_table)
    assert_text I18n.t("owner.tables.qr_title", table: "Tavolo 30"), wait: 5
    assert_selector "#qr-code svg"
  end

  test "sidebar links to the tables area" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)
    visit owner_restaurant_path(id: restaurant.id)
    assert_text "Osteria del Borgo", wait: 5

    within ".drawer-side" do
      click_link I18n.t("owner.restaurants.tables")
    end
    assert_current_path owner_restaurant_tables_path(restaurant_id: restaurant.id)
    assert_selector ".drawer-side a.menu-active", text: I18n.t("owner.restaurants.tables")
  end

  test "bulk print page shows a QR card per active table" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit bulk_print_owner_restaurant_tables_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.tables.bulk_print_title"), wait: 5
    assert_selector ".qr-card", count: restaurant.restaurant_tables.active.count
  end

  test "owner bulk-generates tables by floor" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit owner_restaurant_tables_path(restaurant_id: restaurant)
    click_on I18n.t("owner.tables.bulk.generate")

    fill_in I18n.t("owner.tables.bulk.floors_count"), with: 2
    fill_in I18n.t("owner.tables.bulk.tables_per_floor"), with: 3
    fill_in I18n.t("owner.tables.bulk.floor_label"), with: "Piano"
    choose I18n.t("owner.tables.bulk.patterns.t_number")
    click_on I18n.t("owner.tables.bulk.submit")

    assert_text I18n.t("owner.tables.bulk.created", created: 6)
    # Area headings are CSS-uppercased; newer Chrome returns the transformed
    # text, so match case-insensitively.
    assert_text(/piano 1/i)
    assert_text(/piano 2/i)
    assert_text "T3"
  end

  test "owner deletes all tables from the generator page" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit bulk_new_owner_restaurant_tables_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.tables.bulk.title"), wait: 5

    accept_confirm do
      click_on I18n.t("owner.tables.bulk.delete_all")
    end

    assert_current_path owner_restaurant_tables_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.tables.empty_title"), wait: 5
    assert_equal 0, restaurant.restaurant_tables.count
  end

  test "delete-all-tables button is hidden when the restaurant has no tables" do
    sign_in_as_owner
    restaurant = restaurants(:inactive_restaurant)

    visit bulk_new_owner_restaurant_tables_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.tables.bulk.title"), wait: 5
    assert_no_text I18n.t("owner.tables.bulk.delete_all")
  end
end
