require "test_helper"

module Owner
  class WineLookupsControllerTest < ActionDispatch::IntegrationTest
    setup do
      WineReference.create!(
        external_id: "ref-barolo", name: "Barolo Riserva", producer: "Giacomo Conterno",
        region: "Piemonte", country: "Italy", grape_variety: "Nebbiolo", color: "red",
        vintages: [ 2016, 2018 ]
      )
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
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "barolo")

      assert_response :success
      payload = JSON.parse(response.body)
      assert_equal 1, payload.size
      assert_equal(
        { "name" => "Barolo Riserva", "producer" => "Giacomo Conterno", "region" => "Piemonte",
          "grape_variety" => "Nebbiolo", "vintage_year" => 2018, "color" => "red" },
        payload.first
      )
    end

    test "matches on the producer as well as the name" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "conterno")

      assert_response :success
      assert_equal [ "Barolo Riserva" ], JSON.parse(response.body).map { |wine| wine["name"] }
    end

    test "returns [] for short queries" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "ba")

      assert_response :success
      assert_equal [], JSON.parse(response.body)
    end

    test "returns [] for overlong queries" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "a" * 101)

      assert_response :success
      assert_equal [], JSON.parse(response.body)
    end

    test "returns [] when nothing matches" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "nonexistent wine xyz")

      assert_response :success
      assert_equal [], JSON.parse(response.body)
    end
  end
end
