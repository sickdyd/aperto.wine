require "application_system_test_case"

class OwnerRestaurantTablesTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "My Restaurants", wait: 5
  end

  test "owner can create a table and open its QR code" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit owner_restaurant_tables_path(restaurant_id: restaurant)
    assert_text "Dining Tables", wait: 5
    # Area headings are CSS-uppercased, so match case-insensitively.
    assert_text(/sala principale/i)

    click_link "Add Table", match: :first
    assert_text "New Table", wait: 5

    fill_in "Table Name", with: "Tavolo 30"
    fill_in "Room / Area", with: "Terrazza"
    find("input[type='submit']").click

    assert_text "Table created.", wait: 5
    assert_text "Tavolo 30"
    assert_text(/terrazza/i)

    # Open the new table's QR page
    new_table = RestaurantTable.find_by!(name: "Tavolo 30")
    visit qr_owner_restaurant_table_path(restaurant_id: restaurant, id: new_table)
    assert_text "QR Code — Tavolo 30", wait: 5
    assert_selector "#qr-code svg"
  end

  test "sidebar links to the tables area" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)
    visit owner_restaurant_path(id: restaurant.id)
    assert_text "Osteria del Borgo", wait: 5

    within ".drawer-side" do
      click_link "Dining Tables"
    end
    assert_current_path owner_restaurant_tables_path(restaurant_id: restaurant.id)
    assert_selector ".drawer-side a.menu-active", text: "Dining Tables"
  end

  test "bulk print page shows a QR card per active table" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit bulk_print_owner_restaurant_tables_path(restaurant_id: restaurant)
    assert_text "Print QR Codes", wait: 5
    assert_selector ".qr-card", count: restaurant.restaurant_tables.active.count
  end
end
