require "test_helper"

# Locale resolution priority, highest first:
#   1. an explicit :locale param (the footer switcher / a shared /en URL)
#   2. an override remembered from an earlier switcher click
#   3. the browser's Accept-Language header, ranked by q-value
#   4. I18n.default_locale (:it in every env but test)
class LocaleNegotiationTest < ActionDispatch::IntegrationTest
  ENGLISH_BROWSER = { "HTTP_ACCEPT_LANGUAGE" => "en-US,en;q=0.9" }.freeze
  ITALIAN_BROWSER = { "HTTP_ACCEPT_LANGUAGE" => "it-IT,it;q=0.9" }.freeze

  # The suite runs with default_locale :en so every other test can assert
  # English copy (see config/environments/test.rb). Negotiation is only
  # meaningful against the production default, so pin it back to :it here.
  # Tests run in forked processes, so this never leaks across workers.
  def with_italian_default
    previous_default = I18n.default_locale
    # I18n.locale is fiber-local and lazily initialised from default_locale.
    # The first with_locale inside this block would otherwise pin it to :it for
    # the rest of the worker process, quietly translating later tests in this
    # process into Italian.
    previous_locale = I18n.locale
    I18n.default_locale = :it
    yield
  ensure
    I18n.default_locale = previous_default
    I18n.locale = previous_locale
  end

  def assert_page_locale(expected)
    assert_response :success
    assert_select "html[lang=?]", expected.to_s
  end

  # --- Accept-Language is honoured ---

  test "an English browser gets the English site" do
    with_italian_default do
      get "/", headers: ENGLISH_BROWSER
      assert_page_locale :en
    end
  end

  test "an Italian browser gets the Italian site" do
    with_italian_default do
      get "/", headers: ITALIAN_BROWSER
      assert_page_locale :it
    end
  end

  # --- Italian is the fallback for everyone else ---

  test "a browser asking for a language the site does not speak falls back to Italian" do
    with_italian_default do
      get "/", headers: { "HTTP_ACCEPT_LANGUAGE" => "fr-FR,fr;q=0.9,de;q=0.8" }
      assert_page_locale :it
    end
  end

  test "a request with no Accept-Language header falls back to Italian" do
    with_italian_default do
      get "/"
      assert_page_locale :it
    end
  end

  # --- an explicit choice beats the browser ---

  test "an explicit locale in the path beats the browser language" do
    with_italian_default do
      get "/it", headers: ENGLISH_BROWSER
      assert_page_locale :it
    end
  end

  test "choosing Italian on an English browser survives later unprefixed requests" do
    with_italian_default do
      get "/it", headers: ENGLISH_BROWSER
      assert_page_locale :it

      # default_url_options omits the prefix once the locale matches the
      # default, so the next click lands here with no :locale param at all.
      # Without a remembered choice the header would drag the visitor back
      # to English.
      get "/", headers: ENGLISH_BROWSER
      assert_page_locale :it
    end
  end

  test "choosing English on an Italian browser survives later requests" do
    with_italian_default do
      get "/en", headers: ITALIAN_BROWSER
      assert_page_locale :en

      get "/", headers: ITALIAN_BROWSER
      assert_page_locale :en
    end
  end

  test "switching back replaces the remembered choice" do
    with_italian_default do
      get "/en", headers: ITALIAN_BROWSER
      assert_page_locale :en

      get "/it", headers: ITALIAN_BROWSER
      assert_page_locale :it

      get "/", headers: ITALIAN_BROWSER
      assert_page_locale :it
    end
  end

  # --- only a real override is remembered ---

  test "following ordinary prefixed links never creates a preference" do
    with_italian_default do
      # An English browser gets /en on every internal link, so the param is
      # present on clicks that have nothing to do with the switcher. Recording
      # those would hand the next visitor of a shared browser someone else's
      # language.
      get "/en", headers: ENGLISH_BROWSER
      assert_page_locale :en
      assert_nil session[:locale]
    end
  end

  test "picking the language the browser already asks for drops an earlier override" do
    with_italian_default do
      get "/it", headers: ENGLISH_BROWSER
      assert_equal "it", session[:locale]

      get "/en", headers: ENGLISH_BROWSER
      assert_nil session[:locale]

      # Back to being led by the browser rather than by a stored choice.
      get "/", headers: ENGLISH_BROWSER
      assert_page_locale :en
    end
  end

  # --- Accept-Language is ranked by q-value ---

  test "the highest q wins even when the header is not in preference order" do
    with_italian_default do
      get "/", headers: { "HTTP_ACCEPT_LANGUAGE" => "it;q=0.5,en;q=0.9" }
      assert_page_locale :en
    end
  end

  test "q=0 means the language is not acceptable" do
    with_italian_default do
      get "/", headers: { "HTTP_ACCEPT_LANGUAGE" => "en;q=0,it;q=0.4" }
      assert_page_locale :it
    end
  end

  test "equal q values fall back to the order the client listed" do
    with_italian_default do
      get "/", headers: { "HTTP_ACCEPT_LANGUAGE" => "en;q=0.8,it;q=0.8" }
      assert_page_locale :en
    end
  end

  test "a lowercase region tag is not mistaken for a second language" do
    with_italian_default do
      get "/", headers: { "HTTP_ACCEPT_LANGUAGE" => "en-us" }
      assert_page_locale :en
    end
  end

  # --- untrusted input ---

  test "an unsupported locale param falls back instead of raising" do
    with_italian_default do
      get "/", params: { locale: "de" }, headers: ENGLISH_BROWSER
      assert_page_locale :en
    end
  end

  test "an unsupported locale param is never remembered" do
    with_italian_default do
      get "/", params: { locale: "de" }
      assert_nil session[:locale]
    end
  end

  # The remaining untrusted source is a session carrying a locale the app no
  # longer speaks — only reachable after a deploy drops one from
  # available_locales, so it is covered against the guard itself in
  # test/controllers/application_controller_test.rb rather than by mutating
  # I18n's global state mid-suite.
end
