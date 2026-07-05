require "application_system_test_case"

class OwnerAddressAutocompleteTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "My Restaurants", wait: 5
  end

  def visit_new_restaurant_form
    sign_in_as_owner
    click_link "Add Restaurant", match: :first
    assert_text "New Restaurant", wait: 5
  end

  test "form has hidden coordinate fields and no visible coordinate inputs" do
    visit_new_restaurant_form

    assert_selector "input[name='restaurant[latitude]']", visible: :hidden
    assert_selector "input[name='restaurant[longitude]']", visible: :hidden
    assert_no_selector "input[type='number'][name='restaurant[latitude]']"
    assert_no_text "Latitude"
  end

  test "picking a suggestion fills the hidden coordinates" do
    stub_photon([ photon_feature ])
    visit_new_restaurant_form

    fill_in "Address", with: "Via Roma 42"
    assert_selector "li[role='option']", text: "Via Roma 42, 20121 Milano, Italia", wait: 5
    assert_text "OpenStreetMap contributors"
    find("li[role='option']", match: :first).click

    assert_equal "45.4642", find("input[name='restaurant[latitude]']", visible: false).value
    assert_equal "9.19", find("input[name='restaurant[longitude]']", visible: false).value
  end

  test "editing the address after picking clears the coordinates" do
    stub_photon([ photon_feature ])
    visit_new_restaurant_form

    fill_in "Address", with: "Via Roma 42"
    assert_selector "li[role='option']", wait: 5
    find("li[role='option']", match: :first).click
    assert_equal "45.4642", find("input[name='restaurant[latitude]']", visible: false).value

    fill_in "Address", with: "Something else entirely"

    assert_equal "", find("input[name='restaurant[latitude]']", visible: false).value
    assert_equal "", find("input[name='restaurant[longitude]']", visible: false).value
  end
end
