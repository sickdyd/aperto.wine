require "application_system_test_case"

# The type-ahead is backed by the local wine_references table, so the only
# setup a browser test needs is a seeded reference row.
class WineAutofillTest < ApplicationSystemTestCase
  # The vintage is part of the label on purpose: it is the value the autofill
  # writes into the form, so the owner has to be able to see it before picking.
  SUGGESTION = "Sassicaia 2019 — Tenuta San Guido (Toscana)".freeze

  setup do
    WineReference.create!(
      external_id: "ref-sassicaia", name: "Sassicaia", producer: "Tenuta San Guido",
      region: "Toscana", country: "Italy", grape_variety: "Cabernet Sauvignon",
      color: "red", vintages: [ 2017, 2019 ]
    )
  end

  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text I18n.t("owner.restaurants.title"), wait: 5
  end

  test "selecting a suggestion fills the descriptive fields" do
    sign_in_as_owner
    visit new_owner_restaurant_wine_path(restaurant_id: restaurants(:osteria))

    fill_in "wine[name]", with: "sassicaia"
    assert_text SUGGESTION, wait: 5

    find("[data-wine-autofill-target='results'] button", match: :first).click

    assert_field "wine[name]", with: "Sassicaia"
    assert_field "wine[producer]", with: "Tenuta San Guido"
    assert_field "wine[grape_variety]", with: "Cabernet Sauvignon"
    assert_field "wine[vintage_year]", with: "2019"
    assert_field "wine[region]", with: "Toscana"
    assert_equal "red", find("select[name='wine[color]']").value
  end

  test "matching the producer also surfaces the wine" do
    sign_in_as_owner
    visit new_owner_restaurant_wine_path(restaurant_id: restaurants(:osteria))

    fill_in "wine[name]", with: "tenuta san"
    assert_text SUGGESTION, wait: 5
  end

  test "keyboard-only: arrow down and enter selects, escape closes" do
    sign_in_as_owner
    visit new_owner_restaurant_wine_path(restaurant_id: restaurants(:osteria))

    fill_in "wine[name]", with: "sassicaia"
    assert_text SUGGESTION, wait: 5

    name_input = find("input[name='wine[name]']")
    name_input.send_keys :escape
    assert_no_text SUGGESTION

    # Re-open and select with keyboard only
    name_input.send_keys " "
    name_input.send_keys :backspace
    assert_text SUGGESTION, wait: 5
    name_input.send_keys :arrow_down
    name_input.send_keys :enter

    assert_field "wine[producer]", with: "Tenuta San Guido"
    assert_field "wine[region]", with: "Toscana"
  end
end
