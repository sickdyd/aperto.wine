require "test_helper"

# Every locale that reaches I18n.with_locale passes through #supported_locale
# first. Anything it lets through that I18n does not recognise is a 500, so the
# guard is pinned down directly here; the resolution order it feeds is covered
# in test/integration/locale_negotiation_test.rb.
class ApplicationControllerTest < ActiveSupport::TestCase
  def supported_locale(value)
    ApplicationController.new.send(:supported_locale, value)
  end

  test "accepts a supported locale as a string or a symbol" do
    assert_equal :it, supported_locale("it")
    assert_equal :it, supported_locale(:it)
    assert_equal :en, supported_locale("en")
  end

  test "rejects a locale the app does not speak" do
    assert_nil supported_locale("de")
    assert_nil supported_locale(:de)
  end

  test "rejects blank and missing values" do
    assert_nil supported_locale(nil)
    assert_nil supported_locale("")
    assert_nil supported_locale("   ")
  end

  test "rejects junk without raising" do
    assert_nil supported_locale("en; DROP TABLE users")
    assert_nil supported_locale("../../etc/passwd")
    assert_nil supported_locale([ "en" ])
    assert_nil supported_locale({ "en" => 1 })
  end
end
