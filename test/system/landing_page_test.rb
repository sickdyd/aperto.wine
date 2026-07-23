require "application_system_test_case"

class LandingPageTest < ApplicationSystemTestCase
  test "visitor can see the landing page" do
    visit root_path

    assert_selector "nav"
    assert_text I18n.t("app_name")
  end

  test "visitor sees sign in and sign up links in nav" do
    visit root_path

    within "nav" do
      assert_link I18n.t("landing.sign_in")
      assert_link I18n.t("landing.sign_up")
    end
  end

  test "sign in link navigates to sign in page" do
    visit root_path

    within "nav" do
      click_link I18n.t("landing.sign_in")
    end

    assert_current_path sign_in_path
    assert_selector "h1", text: I18n.t("auth.sign_in")
  end

  test "sign up link navigates to sign up page" do
    visit root_path

    within "nav" do
      click_link I18n.t("landing.sign_up")
    end

    assert_current_path sign_up_path
    assert_selector "h1", text: I18n.t("auth.sign_up")
  end

  test "signed-in user sees their name in nav instead of sign-in links" do
    user = users(:customer)
    visit sign_in_path

    fill_in I18n.t("auth.email"), with: user.email
    fill_in I18n.t("auth.password"), with: "password123"
    click_button I18n.t("auth.sign_in")

    # Should be on root after sign-in as customer
    assert_current_path root_path

    within "nav" do
      assert_text user.name
      assert_no_link I18n.t("landing.sign_in")
      assert_no_link I18n.t("landing.sign_up")
    end
  end
end
