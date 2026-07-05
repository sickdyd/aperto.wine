require "test_helper"
require "webmock/minitest"

module Owner
  class WineLookupsControllerTest < ActionDispatch::IntegrationTest
    API_URL = "https://api.example.test/wine-check"

    setup do
      ENV["WINE_SEARCHER_API_KEY"] = "test-key"
      ENV["WINE_SEARCHER_API_URL"] = API_URL
    end

    teardown do
      ENV.delete("WINE_SEARCHER_API_KEY")
      ENV.delete("WINE_SEARCHER_API_URL")
    end

    test "requires authentication" do
      get owner_wine_lookups_path(q: "barolo")
      assert_redirected_to sign_in_path
    end

    test "requires owner role" do
      sign_in_as users(:customer)
      get owner_wine_lookups_path(q: "barolo")
      assert_response :redirect
    end

    test "returns mapped results as JSON" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo"))
        .to_return(status: 200, body: {
          "wines" => [ { "wine-name" => "Barolo Riserva", "region" => "Piemonte", "grape" => "Nebbiolo",
                         "vintage" => "2018", "wine-type" => "Red" } ]
        }.to_json)

      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "barolo")

      assert_response :success
      payload = JSON.parse(response.body)
      assert_equal 1, payload.size
      assert_equal(
        { "name" => "Barolo Riserva", "producer" => nil, "region" => "Piemonte",
          "grape_variety" => "Nebbiolo", "vintage_year" => 2018, "color" => "red" },
        payload.first
      )
    end

    test "returns [] for short queries without calling the API" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "ba")

      assert_response :success
      assert_equal [], JSON.parse(response.body)
      assert_not_requested :get, /api\.example\.test/
    end

    test "returns [] for overlong queries without calling the API" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "a" * 101)

      assert_response :success
      assert_equal [], JSON.parse(response.body)
      assert_not_requested :get, /api\.example\.test/
    end

    test "returns [] when no API key is configured" do
      ENV.delete("WINE_SEARCHER_API_KEY")
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "barolo")

      assert_response :success
      assert_equal [], JSON.parse(response.body)
    end
  end
end
