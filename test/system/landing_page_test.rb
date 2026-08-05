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

  test "hero carries the headline, both CTAs and the engraving" do
    visit root_path

    assert_selector "main h1", text: "Every great bottle"
    assert_selector "main h1", text: "deserves to be opened"

    assert_link I18n.t("landing.cta_restaurant")
    assert_link I18n.t("landing.cta_customer")

    # Decorative, so it is hidden from the accessibility tree — assert on the
    # markup rather than through Capybara's visible-text lookup.
    assert_selector "main .engraving[aria-hidden='true'] svg.engraving-plate", visible: :all
  end

  test "the how-it-works section lists every step in order" do
    visit root_path

    assert_selector "h2", text: I18n.t("landing.how_title")

    steps = I18n.t("landing.steps")
    steps.each_with_index do |step, i|
      assert_selector "ol li:nth-child(#{i + 1}) h3", text: step[:title]
      assert_text step[:description]
    end
  end

  test "both audiences are addressed with their own heading and link" do
    visit root_path

    assert_selector "h2", text: I18n.t("landing.restaurants_title")
    assert_selector "h2", text: I18n.t("landing.customers_title")
    assert_link I18n.t("landing.restaurants_cta")
    assert_link I18n.t("landing.customers_cta")
  end

  test "footer offers both locales and marks the current one" do
    visit root_path

    within "footer" do
      assert_link "EN", href: root_path(locale: :en)
      assert_link "IT", href: root_path(locale: :it)
      assert_selector "a[aria-current='true']", text: "EN"
    end
  end

  test "switching to Italian translates the page" do
    visit root_path

    within "footer" do
      click_link "IT"
    end

    # Synchronise on the navigation before asserting on the new document.
    assert_current_path root_path(locale: :it)
    assert_selector "h2", text: I18n.t("landing.how_title", locale: :it)
    within "footer" do
      assert_selector "a[aria-current='true']", text: "IT"
    end
  end
end
