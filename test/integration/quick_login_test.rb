require "test_helper"

# The quick-login buttons only pre-fill the sign-in form — the submitted password
# is still verified as normal. What matters is that they never appear on a
# deployment that has not opted in.
class QuickLoginTest < ActionDispatch::IntegrationTest
  setup do
    @original = ENV["SHOW_DEV_LOGIN"]
  end

  teardown do
    ENV["SHOW_DEV_LOGIN"] = @original
  end

  test "quick login is hidden when SHOW_DEV_LOGIN is not set" do
    ENV.delete("SHOW_DEV_LOGIN")

    get sign_in_path

    assert_response :success
    assert_select "[data-action='dev-login#fill']", false,
      "quick login must not render without an explicit opt-in"
  end

  test "quick login is shown when SHOW_DEV_LOGIN is 1" do
    ENV["SHOW_DEV_LOGIN"] = "1"

    get sign_in_path

    assert_response :success
    assert_select "[data-action='dev-login#fill']", 3
  end

  test "quick login stays hidden for any value other than 1" do
    [ "0", "true", "yes", "" ].each do |value|
      ENV["SHOW_DEV_LOGIN"] = value

      get sign_in_path

      assert_select "[data-action='dev-login#fill']", false,
        "SHOW_DEV_LOGIN=#{value.inspect} must not enable quick login"
    end
  end

  test "quick login buttons carry no session-granting capability" do
    ENV["SHOW_DEV_LOGIN"] = "1"

    get sign_in_path

    # They are plain type=button elements that fill inputs client-side. If one
    # ever became a link or a form submit, it would be a way into an account
    # without a password.
    css_select("[data-action='dev-login#fill']").each do |button|
      assert_equal "button", button.name
      assert_equal "button", button["type"]
    end
  end
end
