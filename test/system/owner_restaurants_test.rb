require "application_system_test_case"

class OwnerRestaurantsTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text I18n.t("owner.restaurants.title"), wait: 5
  end

  # ── Index ─────────────────────────────────────────────────────────────────

  test "owner can see their restaurants list" do
    sign_in_as_owner

    assert_selector "h1", text: I18n.t("owner.restaurants.title")
    assert_text "Osteria del Borgo"
  end

  test "owner sees add restaurant button" do
    sign_in_as_owner

    assert_link I18n.t("owner.restaurants.add")
  end

  # ── Create ────────────────────────────────────────────────────────────────

  test "owner can create a new restaurant" do
    sign_in_as_owner

    click_link I18n.t("owner.restaurants.add"), match: :first
    assert_text I18n.t("owner.restaurants.new_title"), wait: 5

    fill_in I18n.t("owner.restaurants.form.name"), with: "La Trattoria"
    fill_in I18n.t("owner.restaurants.form.address"), with: "Via Verdi 10, Torino"
    find("input[type='submit']").click

    assert_text I18n.t("owner.restaurants.created"), wait: 5
    assert_text "La Trattoria"
  end

  test "owner sees validation error when creating restaurant without required fields" do
    sign_in_as_owner

    click_link I18n.t("owner.restaurants.add")

    # Fill only name (address is also required) then clear it to trigger server-side
    fill_in I18n.t("owner.restaurants.form.name"), with: "Missing Address"
    # Address field intentionally left blank; clear via JS to bypass HTML5 required
    page.execute_script("document.querySelector('input[name=\"restaurant[address]\"]').removeAttribute('required')")
    click_button I18n.t("helpers.submit.create", model: Restaurant.model_name.human)

    assert_selector "[role='alert']"
    assert_text "#{Restaurant.human_attribute_name(:address)} #{I18n.t("errors.messages.blank")}"
  end

  # ── Edit ──────────────────────────────────────────────────────────────────

  test "owner can edit an existing restaurant" do
    sign_in_as_owner

    restaurant = restaurants(:osteria)
    visit edit_owner_restaurant_path(id: restaurant.id)

    fill_in I18n.t("owner.restaurants.form.name"), with: "Osteria Aggiornata"
    click_button I18n.t("helpers.submit.update", model: Restaurant.model_name.human)

    assert_text I18n.t("owner.restaurants.updated")
    assert_text "Osteria Aggiornata"
  end

  test "owner can navigate to edit from restaurant show page" do
    sign_in_as_owner

    restaurant = restaurants(:osteria)
    visit owner_restaurant_path(id: restaurant.id)

    click_link I18n.t("shared.edit")
    assert_current_path edit_owner_restaurant_path(id: restaurant.id)
  end

  # ── Delete ────────────────────────────────────────────────────────────────

  test "owner can delete a restaurant" do
    sign_in_as_owner

    # Create a new restaurant to safely delete without fixture side-effects
    click_link I18n.t("owner.restaurants.add")
    fill_in I18n.t("owner.restaurants.form.name"), with: "To Delete"
    fill_in I18n.t("owner.restaurants.form.address"), with: "Via Elimina 1, Roma"
    click_button I18n.t("helpers.submit.create", model: Restaurant.model_name.human)
    assert_text I18n.t("owner.restaurants.created")

    # We are now on the show page for the new restaurant — delete from here
    accept_confirm do
      click_button I18n.t("shared.delete")
    end

    assert_current_path owner_restaurants_path
    assert_text I18n.t("owner.restaurants.deleted")
    assert_no_text "To Delete"
  end

  # ── Menu preview ──────────────────────────────────────────────────────────

  test "owner sees a preview menu card linking to the public menu" do
    sign_in_as_owner

    restaurant = restaurants(:osteria)
    visit owner_restaurant_path(id: restaurant.id)

    link = find_link(I18n.t("owner.restaurants.preview_menu"))
    assert_equal menu_path(id: restaurant.id), URI.parse(link[:href]).path
    assert_equal "_blank", link[:target]
    assert_includes link[:rel], "noopener"
  end

  test "preview menu card is disabled for an inactive restaurant" do
    sign_in_as_owner

    restaurant = restaurants(:inactive_restaurant)
    visit owner_restaurant_path(id: restaurant.id)

    assert_no_link I18n.t("owner.restaurants.preview_menu")
    assert_text I18n.t("owner.restaurants.preview_inactive_hint")
  end

  # ── Auth guard ────────────────────────────────────────────────────────────

  test "unauthenticated user is redirected away from owner restaurants" do
    visit owner_restaurants_path

    assert_current_path sign_in_path
  end

  test "customer is redirected away from owner area" do
    user = users(:customer)
    visit sign_in_path
    fill_in I18n.t("auth.email"), with: user.email
    fill_in I18n.t("auth.password"), with: "password123"
    click_button I18n.t("auth.sign_in")
    # Customer lands on root after sign-in
    assert_current_path root_path

    # Attempting to visit the owner area should redirect away
    visit owner_restaurants_path
    # require_role! redirects to root_path
    assert_current_path root_path
  end
end
