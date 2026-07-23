require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "sign in page renders correctly" do
    visit sign_in_path

    assert_selector "h1", text: I18n.t("auth.sign_in")
    assert_field I18n.t("auth.email")
    assert_field I18n.t("auth.password")
    assert_button I18n.t("auth.sign_in")
  end

  test "customer can sign in and is redirected to root" do
    user = users(:customer)

    visit sign_in_path

    fill_in I18n.t("auth.email"), with: user.email
    fill_in I18n.t("auth.password"), with: "password123"
    click_button I18n.t("auth.sign_in")

    assert_current_path root_path
    # The application layout (home page) does not render flash, so we verify
    # that the user is now signed in by checking their name in the nav.
    assert_text user.name
  end

  test "owner can sign in and is redirected to owner restaurants" do
    user = users(:owner)

    visit sign_in_path

    fill_in I18n.t("auth.email"), with: user.email
    fill_in I18n.t("auth.password"), with: "password123"
    click_button I18n.t("auth.sign_in")

    assert_current_path owner_restaurants_path
    # Owner layout renders flash messages
    assert_text I18n.t("auth.signed_in")
  end

  test "shows error on invalid credentials" do
    visit sign_in_path

    fill_in I18n.t("auth.email"), with: "nobody@example.com"
    fill_in I18n.t("auth.password"), with: "wrongpassword"
    click_button I18n.t("auth.sign_in")

    assert_selector "[role='alert']"
    assert_text I18n.t("auth.invalid_credentials")
    assert_current_path sign_in_path
  end

  test "shows error for correct email but wrong password" do
    user = users(:customer)

    visit sign_in_path

    fill_in I18n.t("auth.email"), with: user.email
    fill_in I18n.t("auth.password"), with: "wrongpassword"
    click_button I18n.t("auth.sign_in")

    assert_selector "[role='alert']"
    assert_text I18n.t("auth.invalid_credentials")
  end

  test "sign up link is present on sign in page" do
    visit sign_in_path

    assert_link I18n.t("auth.sign_up_link")
    click_link I18n.t("auth.sign_up_link")
    assert_current_path sign_up_path
  end

  test "protected page redirects unauthenticated user to sign in" do
    visit owner_restaurants_path

    assert_current_path sign_in_path
    assert_text I18n.t("auth.sign_in_required")
  end
end
