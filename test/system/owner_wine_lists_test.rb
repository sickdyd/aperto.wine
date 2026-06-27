require "application_system_test_case"

class OwnerWineListsTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "My Restaurants", wait: 5
  end

  test "owner can create a curated wine list and add a wine to it" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit owner_restaurant_wine_lists_path(restaurant_id: restaurant)
    assert_text "Curated Lists", wait: 5

    click_link "Add List", match: :first
    assert_text "New Wine List", wait: 5

    fill_in "List Name", with: "Spring Picks"
    find("input[type='submit']").click

    assert_text "Wine list created.", wait: 5
    assert_text "Spring Picks"

    # Edit the new list and add a wine to it
    new_list = WineList.find_by!(name: "Spring Picks")
    visit edit_owner_restaurant_wine_list_path(restaurant_id: restaurant, id: new_list)
    assert_text "Wines on this list", wait: 5

    select "Barolo Riserva", from: "wine_id"
    click_button "Add"

    assert_text "Wine added to the list.", wait: 5
    assert_text "Barolo Riserva"
  end

  test "owner sees an empty state when no lists exist" do
    sign_in_as_owner
    # trattoria belongs to owner_two; osteria has only inactive lists but they
    # still exist, so use a fresh restaurant with no lists via the picker.
    restaurant = users(:owner).restaurants.create!(
      name: "Empty Cellar", address: "Via Vuota 1", proximity_radius_meters: 100
    )

    visit owner_restaurant_wine_lists_path(restaurant_id: restaurant)
    assert_text "No curated lists yet", wait: 5
    assert_link "Create your first list"
  end
end
