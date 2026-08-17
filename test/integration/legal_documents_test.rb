require "test_helper"

# The two public legal documents. They are the only pages on the site that
# exist because the law says so, which makes their failure mode unusual: a
# 404 or a missing section is a compliance gap, not a cosmetic bug.
class LegalDocumentsTest < ActionDispatch::IntegrationTest
  IDENTITY = {
    "LEGAL_NAME" => "Aperto Wine S.r.l.",
    "LEGAL_ADDRESS" => "Via Roma 1, 20121 Milano (MI), Italia",
    "LEGAL_EMAIL" => "legal@aperto.wine",
    "LEGAL_PHONE" => "+39 02 1234567",
    "LEGAL_VAT_NUMBER" => "IT01234567890",
    "LEGAL_REA_NUMBER" => "MI-1234567"
  }.freeze

  setup do
    @osteria = restaurants(:osteria)
  end

  # The identity comes from the environment (config/legal.yml re-reads it on
  # every call), so the honest way to exercise both states is to set it and put
  # it back — no stubbing, and the ERB in the config file gets covered too.
  def with_identity(values)
    previous = IDENTITY.keys.index_with { |name| ENV[name] }
    IDENTITY.each_key { |name| ENV[name] = values[name] }
    yield
  ensure
    previous.each { |name, value| ENV[name] = value }
  end

  # --- reachability ---

  test "both documents are public, no session required" do
    [ privacy_path, terms_path ].each do |path|
      get path
      assert_response :success
    end
  end

  test "both documents render in Italian and in English" do
    %i[it en].each do |locale|
      get privacy_path(locale: locale)
      assert_response :success
      assert_select "html[lang=?]", locale.to_s

      get terms_path(locale: locale)
      assert_response :success
      assert_select "html[lang=?]", locale.to_s
    end
  end

  test "the Italian privacy notice is written in Italian, not falling back to English" do
    get privacy_path(locale: :it)

    assert_match(/Informativa/i, response.body)
    assert_match(/titolare del trattamento/i, response.body)
  end

  test "the English privacy notice is written in English, not falling back to Italian" do
    get privacy_path(locale: :en)

    assert_match(/Privacy Notice/i, response.body)
    assert_match(/data controller/i, response.body)
  end

  # --- privacy notice content (GDPR art. 13) ---

  test "the privacy notice names what is collected on the diner side" do
    get privacy_path(locale: :en)

    assert_match(/guest name/i, response.body)
    assert_match(/table/i, response.body)
    assert_match(/24 hours/i, response.body, "the OrderHistory cookie lifetime must be stated")
  end

  test "the privacy notice explains the controller/processor split" do
    get privacy_path(locale: :en)

    assert_match(/processor/i, response.body)
    assert_match(/restaurant is the\s+(data\s+)?controller/i, response.body)
  end

  test "the privacy notice lists the sub-processors actually engaged" do
    get privacy_path(locale: :en)

    assert_match(/Render/, response.body)
    assert_match(/Frankfurt/i, response.body)
    assert_match(/Photon/i, response.body)
  end

  test "the privacy notice tells the reader how to complain to the supervisory authority" do
    get privacy_path(locale: :it)

    assert_match(/Garante per la protezione dei dati personali/i, response.body)
  end

  # --- terms content ---

  test "the terms place the wine contract between diner and restaurant" do
    get terms_path(locale: :en)

    assert_match(/technical intermediary/i, response.body)
    assert_match(/between the guest and\s+the restaurant/i, response.body)
  end

  test "the terms carry the art. 28 processing agreement for restaurants" do
    get terms_path(locale: :en)

    assert_match(/Article 28/i, response.body)
    assert_match(/sub-processor/i, response.body)
  end

  test "the terms state that alcohol is not served to minors and staff verify age" do
    get terms_path(locale: :it)

    assert_match(/18/, response.body)
    assert_match(/documento/i, response.body)
  end

  # --- operator identity (D.Lgs. 70/2003 art. 7) ---

  test "the operator identity is published on both documents when configured" do
    with_identity(IDENTITY) do
      [ privacy_path, terms_path ].each do |path|
        get path
        assert_response :success
        assert_match IDENTITY["LEGAL_NAME"], response.body
        assert_match IDENTITY["LEGAL_VAT_NUMBER"], response.body
        assert_match IDENTITY["LEGAL_EMAIL"], response.body
        assert_match IDENTITY["LEGAL_PHONE"], response.body
      end
    end
  end

  # An address carries commas and a legal name can carry quotes, both of which
  # would break config/legal.yml if the ERB interpolated them bare.
  test "an identity with punctuation survives the YAML round trip" do
    with_identity(IDENTITY.merge("LEGAL_NAME" => 'Aperto "Wine" S.r.l., società')) do
      get terms_path

      assert_response :success
      assert_match "società", response.body
    end
  end

  # Shipping the block half-filled is the failure this guards: it must read as
  # unfinished rather than silently collapsing to a blank line.
  test "an unconfigured identity renders a visible pending marker" do
    with_identity({}) do
      get terms_path(locale: :it)

      assert_response :success
      assert_match I18n.t("legal.identity.pending", locale: :it), response.body
    end
  end

  # --- reachability from the surfaces that collect data ---

  test "the landing footer links to both documents" do
    get root_path

    assert_select "footer a[href=?]", privacy_path, count: 1
    assert_select "footer a[href=?]", terms_path, count: 1
  end

  test "the public menu links to both documents" do
    get published_menu_path(@osteria)

    assert_select "a[href=?]", privacy_path
    assert_select "a[href=?]", terms_path
  end

  # GDPR art. 13 wants the notice available *where* the data is collected, and
  # the order form is the only place a diner hands over anything.
  test "the order form carries the privacy notice link" do
    barolo = wines(:barolo)
    post cart_items_path(restaurant_slug: @osteria.slug),
         params: { wine_id: barolo.id, glass_size_ml: 125, quantity: 1 }

    get cart_path(restaurant_slug: @osteria.slug)
    assert_response :success
    assert_select "form a[href=?]", privacy_path
    assert_select "form a[href=?]", terms_path
  end

  test "the sign-up form links to both documents" do
    get sign_up_path

    assert_select "a[href=?]", privacy_path
    assert_select "a[href=?]", terms_path
  end
end
