require "application_system_test_case"

class OwnerWineListsTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text I18n.t("owner.restaurants.title"), wait: 5
  end

  test "wine lists header offers a preview of the public menu" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit owner_restaurant_wine_lists_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.wine_lists.title"), wait: 5
    link = find_link(I18n.t("owner.restaurants.preview_menu"))
    assert_equal menu_path(id: restaurant.id), URI.parse(link[:href]).path
    assert_equal "_blank", link[:target]
  end

  test "owner can create a curated wine list and add a wine to it" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)

    visit owner_restaurant_wine_lists_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.wine_lists.title"), wait: 5

    click_link I18n.t("owner.wine_lists.add"), match: :first
    assert_text I18n.t("owner.wine_lists.new_title"), wait: 5

    fill_in I18n.t("owner.wine_lists.form.name"), with: "Spring Picks"
    find("input[type='submit']").click

    assert_text I18n.t("owner.wine_lists.created"), wait: 5
    assert_text "Spring Picks"

    # Edit the new list and add a wine to it
    new_list = WineList.find_by!(name: "Spring Picks")
    visit edit_owner_restaurant_wine_list_path(restaurant_id: restaurant, id: new_list)
    assert_text I18n.t("owner.wine_lists.members.title"), wait: 5

    barolo = restaurant.wines.find_by!(name: "Barolo Riserva")
    within "[data-wine-id='#{barolo.id}']" do
      click_button I18n.t("owner.wine_lists.members.add_to_list")
    end

    assert_text I18n.t("owner.wine_lists.members.added"), wait: 5
    # Members are grouped into one drop container per colour; barolo is red.
    within "[data-sortable-target='members'][data-color='red']" do
      assert_text "Barolo Riserva"
    end
  end

  test "the same wine can be added to two different lists" do
    sign_in_as_owner
    restaurant = restaurants(:osteria)
    wine = restaurant.wines.create!(
      name: "Nebbiolo di Prova", color: :red, bottle_size_ml: 750, available_glasses: 4
    )

    [ wine_lists(:summer), wine_lists(:winter) ].each do |list|
      visit edit_owner_restaurant_wine_list_path(restaurant_id: restaurant, id: list)
      assert_text "Wines on this list", wait: 5

      within "[data-wine-id='#{wine.id}']" do
        click_button "Add to list"
      end
      assert_text "Wine added to the list.", wait: 5
    end

    assert_equal 2, wine.wine_lists.where(id: [ wine_lists(:summer).id, wine_lists(:winter).id ]).count
  end

  test "list edit page points to the shared catalog when the restaurant has no wines" do
    sign_in_as_owner
    restaurant = users(:owner).restaurants.create!(
      name: "Empty Cellar", address: "Via Vuota 1", proximity_radius_meters: 100
    )
    list = restaurant.wine_lists.create!(name: "First List")

    visit edit_owner_restaurant_wine_list_path(restaurant_id: restaurant, id: list)
    assert_text "Your wine catalog is empty", wait: 5

    click_link "Go to My Wines"
    assert_current_path owner_restaurant_wines_path(restaurant_id: restaurant.id)
    assert_text "No wines yet"
  end

  test "a restaurant with no lists shows the empty state" do
    sign_in_as_owner
    restaurant = users(:owner).restaurants.create!(
      name: "Empty Cellar", address: "Via Vuota 1", proximity_radius_meters: 100
    )

    visit owner_restaurant_wine_lists_path(restaurant_id: restaurant)
    assert_text I18n.t("owner.wine_lists.empty_title"), wait: 5
    assert_text I18n.t("owner.wine_lists.empty_description")
    assert_link I18n.t("owner.wine_lists.add_first")
  end
end
