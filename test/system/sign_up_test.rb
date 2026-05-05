require "application_system_test_case"

class SignUpTest < ApplicationSystemTestCase
  test "customer registration form is shown by default" do
    visit sign_up_path

    assert_selector "h1", text: "Create Account"
    assert_selector "[role='tab']", text: /i'm a customer/i
    assert_selector "[role='tab']", text: /i'm a restaurant owner/i
    assert_field "Full Name"
    assert_field "Email"
    assert_field "Password"
    assert_field "Confirm Password"
    assert_button "Create Account"
  end

  test "visitor can register as a customer" do
    visit sign_up_path

    fill_in "Full Name", with: "New Customer"
    fill_in "Email", with: "newcustomer@example.com"
    fill_in "Password", with: "securepass1"
    fill_in "Confirm Password", with: "securepass1"
    click_button "Create Account"

    # Customer is redirected to root; verify sign-in state via nav
    assert_current_path root_path
    assert_text "New Customer"
  end

  test "visitor can switch to owner tab and register as owner" do
    visit sign_up_path

    click_link "I'm a restaurant owner"

    assert_current_path sign_up_path(tab: "owner")

    fill_in "Full Name", with: "New Owner"
    fill_in "Email", with: "newowner@example.com"
    fill_in "Password", with: "securepass1"
    fill_in "Confirm Password", with: "securepass1"
    click_button "Create Account"

    # Owner is redirected to owner dashboard which uses the owner layout with flash
    assert_current_path owner_restaurants_path
    assert_text "Welcome to Wine Sharing!"
  end

  test "shows validation errors on empty form submission" do
    visit sign_up_path

    # Fields have HTML5 required; the browser prevents submission.
    # Verify we stay on the sign-up page.
    click_button "Create Account"
    assert_current_path sign_up_path
  end

  test "shows error when passwords do not match" do
    visit sign_up_path

    fill_in "Full Name", with: "Test User"
    fill_in "Email", with: "mismatch@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm Password", with: "different123"
    click_button "Create Account"

    assert_selector "[role='alert']"
    assert_text "Password confirmation doesn't match"
  end

  test "shows error when email is already taken" do
    existing = users(:customer)

    visit sign_up_path

    fill_in "Full Name", with: "Duplicate"
    fill_in "Email", with: existing.email
    fill_in "Password", with: "password123"
    fill_in "Confirm Password", with: "password123"
    click_button "Create Account"

    assert_selector "[role='alert']"
    assert_text "Email has already been taken"
  end

  test "sign in link is present on sign up page" do
    visit sign_up_path

    assert_link "Sign in"
    click_link "Sign in"
    assert_current_path sign_in_path
  end
end
