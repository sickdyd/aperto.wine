require "application_system_test_case"

class SignUpTest < ApplicationSystemTestCase
  # Mono small caps means the browser reports this copy uppercased; match
  # case-insensitively rather than dropping the assertion.
  def assert_flash_label(key)
    assert_text(/#{Regexp.escape(I18n.t(key))}/i)
  end

  test "customer registration form is shown by default" do
    visit sign_up_path

    assert_selector "h1", text: I18n.t("auth.sign_up")
    assert_selector "[role='tab']", text: /#{Regexp.escape(I18n.t("auth.tab_customer"))}/i
    assert_selector "[role='tab']", text: /#{Regexp.escape(I18n.t("auth.tab_owner"))}/i
    # The selected role is exposed to assistive tech, not carried by fill alone.
    assert_selector "[role='tab'][aria-selected='true']",
                    text: /#{Regexp.escape(I18n.t("auth.tab_customer"))}/i
    assert_field I18n.t("auth.name")
    assert_field I18n.t("auth.email")
    assert_field I18n.t("auth.password")
    assert_field I18n.t("auth.password_confirmation")
    assert_button I18n.t("auth.create_account")
  end

  test "visitor can register as a customer" do
    visit sign_up_path

    fill_in I18n.t("auth.name"), with: "New Customer"
    fill_in I18n.t("auth.email"), with: "newcustomer@example.com"
    fill_in I18n.t("auth.password"), with: "securepass1"
    fill_in I18n.t("auth.password_confirmation"), with: "securepass1"
    click_button I18n.t("auth.create_account")

    # Customer is redirected to root; verify sign-in state via nav
    assert_current_path root_path
    assert_text "New Customer"
  end

  test "visitor can switch to owner tab and register as owner" do
    visit sign_up_path

    click_link I18n.t("auth.tab_owner")

    assert_current_path sign_up_path(tab: "owner")
    assert_selector "[role='tab'][aria-selected='true']",
                    text: /#{Regexp.escape(I18n.t("auth.tab_owner"))}/i

    fill_in I18n.t("auth.name"), with: "New Owner"
    fill_in I18n.t("auth.email"), with: "newowner@example.com"
    fill_in I18n.t("auth.password"), with: "securepass1"
    fill_in I18n.t("auth.password_confirmation"), with: "securepass1"
    click_button I18n.t("auth.create_account")

    # Owner is redirected to owner dashboard which uses the owner layout with flash
    assert_current_path owner_restaurants_path
    assert_text I18n.t("auth.welcome")
  end

  test "shows validation errors on empty form submission" do
    visit sign_up_path

    # Fields have HTML5 required; the browser prevents submission.
    # Verify we stay on the sign-up page.
    click_button I18n.t("auth.create_account")
    assert_current_path sign_up_path
  end

  test "shows error when passwords do not match" do
    visit sign_up_path

    fill_in I18n.t("auth.name"), with: "Test User"
    fill_in I18n.t("auth.email"), with: "mismatch@example.com"
    fill_in I18n.t("auth.password"), with: "password123"
    fill_in I18n.t("auth.password_confirmation"), with: "different123"
    click_button I18n.t("auth.create_account")

    assert_selector "[role='alert']"
    assert_flash_label "shared.flash_error"
    assert_text "#{User.human_attribute_name(:password_confirmation)} " \
                "#{I18n.t("errors.messages.confirmation", attribute: User.human_attribute_name(:password))}"
  end

  test "shows error when email is already taken" do
    existing = users(:customer)

    visit sign_up_path

    fill_in I18n.t("auth.name"), with: "Duplicate"
    fill_in I18n.t("auth.email"), with: existing.email
    fill_in I18n.t("auth.password"), with: "password123"
    fill_in I18n.t("auth.password_confirmation"), with: "password123"
    click_button I18n.t("auth.create_account")

    assert_selector "[role='alert']"
    assert_flash_label "shared.flash_error"
    assert_text "#{User.human_attribute_name(:email)} #{I18n.t("errors.messages.taken")}"
  end

  test "sign in link is present on sign up page" do
    visit sign_up_path

    assert_link I18n.t("auth.sign_in_link")
    click_link I18n.t("auth.sign_in_link")
    assert_current_path sign_in_path
  end
end
