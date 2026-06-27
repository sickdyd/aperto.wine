require "application_system_test_case"

class LandingPageTest < ApplicationSystemTestCase
  test "visitor can see the landing page" do
    visit root_path

    assert_selector "nav"
    assert_text "aperto.wine"
  end

  test "visitor sees sign in and sign up links in nav" do
    visit root_path

    within "nav" do
      assert_link "Sign In"
      assert_link "Get Started"
    end
  end

  test "sign in link navigates to sign in page" do
    visit root_path

    within "nav" do
      click_link "Sign In"
    end

    assert_current_path sign_in_path
    assert_selector "h1", text: "Sign In"
  end

  test "sign up link navigates to sign up page" do
    visit root_path

    within "nav" do
      click_link "Get Started"
    end

    assert_current_path sign_up_path
    assert_selector "h1", text: "Create Account"
  end

  test "signed-in user sees their name in nav instead of sign-in links" do
    user = users(:customer)
    visit sign_in_path

    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"

    # Should be on root after sign-in as customer
    assert_current_path root_path

    within "nav" do
      assert_text user.name
      assert_no_link "Sign In"
      assert_no_link "Get Started"
    end
  end
end
