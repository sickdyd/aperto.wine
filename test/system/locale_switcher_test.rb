require "application_system_test_case"

class LocaleSwitcherTest < ApplicationSystemTestCase
  # Headless Chrome is pinned to Accept-Language: en (see
  # ApplicationSystemTestCase). Running these against the production default of
  # :it is what makes the switcher meaningful: the browser asks for English, so
  # picking Italian has to be remembered rather than re-negotiated on every
  # request. System tests serve the app in this same process, so assigning the
  # default here reaches the server.
  setup do
    @previous_default = I18n.default_locale
    # with_locale snapshots the lazily-derived I18n.locale into place on the
    # Puma thread that serves the first request, and that thread is reused. The
    # app always re-resolves inside switch_locale so nothing reads the stale
    # value today, but restore it anyway — same reasoning as
    # with_italian_default in test/integration/locale_negotiation_test.rb.
    @previous_locale = I18n.locale
    I18n.default_locale = :it
  end

  teardown do
    I18n.default_locale = @previous_default
    I18n.locale = @previous_locale
  end

  test "an English browser lands on the English site" do
    visit "/"

    assert_selector "html[lang='en']"
    assert_link I18n.t("landing.sign_in", locale: :en)
  end

  test "picking Italian sticks while browsing on to another page" do
    visit "/"
    assert_selector "html[lang='en']"

    within "footer" do
      click_link "IT"
    end
    assert_selector "html[lang='it']"

    # The Italian pages carry no /it prefix (it is the default), so this click
    # leaves the app with nothing but the session to go on — the browser is
    # still asking for English.
    click_link I18n.t("landing.sign_in", locale: :it), match: :first

    assert_selector "html[lang='it']"
    assert_selector "h1", text: I18n.t("auth.sign_in", locale: :it)
  end

  # Picking English here matches what this browser already asks for, so the
  # override is dropped rather than stored — the visitor ends up back on plain
  # Accept-Language negotiation, which lands on English all the same.
  test "switching back to English drops the override and stays English" do
    visit "/"

    within "footer" do
      click_link "IT"
    end
    assert_selector "html[lang='it']"

    within "footer" do
      click_link "EN"
    end
    assert_selector "html[lang='en']"

    click_link I18n.t("landing.sign_in", locale: :en), match: :first
    assert_selector "h1", text: I18n.t("auth.sign_in", locale: :en)
  end
end
