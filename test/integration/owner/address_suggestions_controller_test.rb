require "test_helper"

module Owner
  class AddressSuggestionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
    end

    test "index requires authentication" do
      get owner_address_suggestions_path(q: "Via Roma 42")
      assert_redirected_to sign_in_path
    end

    test "index as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_address_suggestions_path(q: "Via Roma 42")
      assert_redirected_to root_path
    end

    test "index renders suggestion options with coordinates and attribution" do
      stub_photon([ photon_feature ])
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Via Roma 42")

      assert_response :success
      assert_match %r{<li[^>]*role="option"}, response.body
      assert_match 'data-autocomplete-value="Via Roma 42, 20121 Milano, Italia"', response.body
      assert_match 'data-latitude="45.4642"', response.body
      assert_match 'data-longitude="9.19"', response.body
      assert_match I18n.t("owner.restaurants.form.address_suggestions_attribution"), response.body
    end

    test "index escapes HTML in photon data" do
      stub_photon([ photon_feature(street: "<script>alert(1)</script>") ])
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Via Roma 42")

      assert_response :success
      refute_match "<script>alert(1)</script>", response.body
    end

    test "index returns empty body for short queries without calling photon" do
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Vi")

      assert_response :success
      assert_empty response.body.strip
      assert_not_requested :get, PhotonStubs::PHOTON_API
    end

    test "index returns empty body when photon fails" do
      stub_request(:get, PhotonStubs::PHOTON_API).to_timeout
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Via Roma 42")

      assert_response :success
      assert_empty response.body.strip
    end

    test "index is rate limited" do
      sign_in_as @owner

      responses = 11.times.map do |i|
        get owner_address_suggestions_path(q: "Via Roma #{i}")
        response.status
      end

      assert_equal 429, responses.last
      assert_includes responses.first(10), 200
    end
  end
end
