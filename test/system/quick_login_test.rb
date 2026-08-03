require "application_system_test_case"

class QuickLoginTest < ApplicationSystemTestCase
  DEMO_EMAIL = "owner@aperto.wine".freeze
  DEMO_PASSWORD = "password".freeze

  setup do
    @original = ENV["SHOW_DEV_LOGIN"]
    ENV["SHOW_DEV_LOGIN"] = "1"

    # The buttons pre-fill the accounts from db/seeds/demo.rb, which are not
    # fixtures — staging gets them by loading that file explicitly.
    User.create!(
      email: DEMO_EMAIL, name: "Marco Rossi", role: :owner,
      password: DEMO_PASSWORD, password_confirmation: DEMO_PASSWORD,
      confirmed_at: Time.current
    )
  end

  teardown do
    ENV["SHOW_DEV_LOGIN"] = @original
  end

  test "a quick login button fills the form and those credentials sign in" do
    visit sign_in_path

    find("button[data-dev-login-email-param='#{DEMO_EMAIL}']").click

    assert_equal DEMO_EMAIL, find("#email").value
    assert_equal DEMO_PASSWORD, find("#password").value

    # The button only fills the form — signing in still goes through the normal
    # password check.
    click_button I18n.t("auth.sign_in")

    assert_text I18n.t("auth.signed_in")
  end

  test "quick login is absent without the opt-in" do
    ENV.delete("SHOW_DEV_LOGIN")

    visit sign_in_path

    assert_selector "#email"
    assert_no_selector "button[data-action='dev-login#fill']"
  end
end
