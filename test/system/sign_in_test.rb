require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "sign in page renders correctly" do
    visit sign_in_path

    assert_selector "h1", text: "Sign In"
    assert_field "Email"
    assert_field "Password"
    assert_button "Sign In"
  end

  test "customer can sign in and is redirected to root" do
    user = users(:customer)

    visit sign_in_path

    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"

    assert_current_path root_path
    # The application layout (home page) does not render flash, so we verify
    # that the user is now signed in by checking their name in the nav.
    assert_text user.name
  end

  test "owner can sign in and is redirected to owner restaurants" do
    user = users(:owner)

    visit sign_in_path

    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"

    assert_current_path owner_restaurants_path
    # Owner layout renders flash messages
    assert_text "Welcome back!"
  end

  test "shows error on invalid credentials" do
    visit sign_in_path

    fill_in "Email", with: "nobody@example.com"
    fill_in "Password", with: "wrongpassword"
    click_button "Sign In"

    assert_selector "[role='alert']"
    assert_text "Invalid email or password."
    assert_current_path sign_in_path
  end

  test "shows error for correct email but wrong password" do
    user = users(:customer)

    visit sign_in_path

    fill_in "Email", with: user.email
    fill_in "Password", with: "wrongpassword"
    click_button "Sign In"

    assert_selector "[role='alert']"
    assert_text "Invalid email or password."
  end

  test "sign up link is present on sign in page" do
    visit sign_in_path

    assert_link "Create one"
    click_link "Create one"
    assert_current_path sign_up_path
  end

  test "protected page redirects unauthenticated user to sign in" do
    visit owner_restaurants_path

    assert_current_path sign_in_path
    assert_text "Please sign in to continue."
  end
end
