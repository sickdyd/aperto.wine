require "application_system_test_case"

class OwnerRestaurantsTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "My Restaurants", wait: 5
  end

  # ── Index ─────────────────────────────────────────────────────────────────

  test "owner can see their restaurants list" do
    sign_in_as_owner

    assert_selector "h1", text: "My Restaurants"
    assert_text "Osteria del Borgo"
  end

  test "owner sees add restaurant button" do
    sign_in_as_owner

    assert_link "Add Restaurant"
  end

  # ── Create ────────────────────────────────────────────────────────────────

  test "owner can create a new restaurant" do
    sign_in_as_owner

    click_link "Add Restaurant", match: :first
    assert_text "New Restaurant", wait: 5

    fill_in "Restaurant Name", with: "La Trattoria"
    fill_in "Address", with: "Via Verdi 10, Torino"
    find("input[type='submit']").click

    assert_text "Restaurant created successfully.", wait: 5
    assert_text "La Trattoria"
  end

  test "owner sees validation error when creating restaurant without required fields" do
    sign_in_as_owner

    click_link "Add Restaurant"

    # Fill only name (address is also required) then clear it to trigger server-side
    fill_in "Restaurant Name", with: "Missing Address"
    # Address field intentionally left blank; clear via JS to bypass HTML5 required
    page.execute_script("document.querySelector('input[name=\"restaurant[address]\"]').removeAttribute('required')")
    click_button "Create Restaurant"

    assert_selector "[role='alert']"
    assert_text "Address can't be blank"
  end

  # ── Edit ──────────────────────────────────────────────────────────────────

  test "owner can edit an existing restaurant" do
    sign_in_as_owner

    restaurant = restaurants(:osteria)
    visit edit_owner_restaurant_path(id: restaurant.id)

    fill_in "Restaurant Name", with: "Osteria Aggiornata"
    click_button "Update Restaurant"

    assert_text "Restaurant updated successfully."
    assert_text "Osteria Aggiornata"
  end

  test "owner can navigate to edit from restaurant show page" do
    sign_in_as_owner

    restaurant = restaurants(:osteria)
    visit owner_restaurant_path(id: restaurant.id)

    click_link "Edit"
    assert_current_path edit_owner_restaurant_path(id: restaurant.id)
  end

  # ── Delete ────────────────────────────────────────────────────────────────

  test "owner can delete a restaurant" do
    sign_in_as_owner

    # Create a new restaurant to safely delete without fixture side-effects
    click_link "Add Restaurant"
    fill_in "Restaurant Name", with: "To Delete"
    fill_in "Address", with: "Via Elimina 1, Roma"
    click_button "Create Restaurant"
    assert_text "Restaurant created successfully."

    # We are now on the show page for the new restaurant — delete from here
    accept_confirm do
      click_button "Delete"
    end

    assert_current_path owner_restaurants_path
    assert_text "Restaurant deleted."
    assert_no_text "To Delete"
  end

  # ── Auth guard ────────────────────────────────────────────────────────────

  test "unauthenticated user is redirected away from owner restaurants" do
    visit owner_restaurants_path

    assert_current_path sign_in_path
  end

  test "customer is redirected away from owner area" do
    user = users(:customer)
    visit sign_in_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    # Customer lands on root after sign-in
    assert_current_path root_path

    # Attempting to visit the owner area should redirect away
    visit owner_restaurants_path
    # require_role! redirects to root_path
    assert_current_path root_path
  end
end
