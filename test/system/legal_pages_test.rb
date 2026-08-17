require "application_system_test_case"

# A legal document nobody can reach is a document that does not exist, so what
# is worth driving in a browser is the *route to* the documents — from the
# landing foot, from the menu a diner actually holds, and back out again.
class LegalPagesTest < ApplicationSystemTestCase
  setup do
    @osteria = restaurants(:osteria)
  end

  test "the landing foot leads to the privacy notice" do
    visit root_path

    within "footer" do
      click_link I18n.t("legal.nav.privacy")
    end

    assert_current_path privacy_path
    assert_selector "h1", text: I18n.t("legal.privacy.title")
  end

  test "the landing foot leads to the terms" do
    visit root_path

    within "footer" do
      click_link I18n.t("legal.nav.terms")
    end

    assert_current_path terms_path
    assert_selector "h1", text: I18n.t("legal.terms.title")
  end

  test "a diner on the menu can reach the privacy notice and come back" do
    visit published_menu_path(@osteria)

    click_link I18n.t("legal.nav.privacy")

    assert_current_path privacy_path
    assert_selector "h1", text: I18n.t("legal.privacy.title")

    click_link I18n.t("legal.back_to_site")
    assert_current_path root_path
  end

  test "the documents keep the reader's locale" do
    visit privacy_path(locale: :it)

    assert_selector "html[lang=it]"
    assert_text "Informativa"

    visit terms_path(locale: :it)

    assert_selector "html[lang=it]"
    assert_selector "h1", text: I18n.t("legal.terms.title", locale: :it)
  end

  test "the documents are navigable by heading, not one undifferentiated wall" do
    visit terms_path

    assert_selector "h2", minimum: 5
  end
end
