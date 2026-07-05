require "test_helper"

class GeocodingTest < ActiveSupport::TestCase
  test "suggestions returns empty for queries shorter than 3 chars without calling photon" do
    assert_equal [], Geocoding.suggestions("Vi")
    assert_equal [], Geocoding.suggestions(nil)
    assert_equal [], Geocoding.suggestions("  V  ")
    assert_not_requested :get, PhotonStubs::PHOTON_API
  end

  test "suggestions maps photon features to labeled coordinates" do
    stub_photon([ photon_feature ])

    suggestions = Geocoding.suggestions("Via Roma 42")

    assert_equal 1, suggestions.length
    assert_equal "Via Roma 42, 20121 Milano, Italia", suggestions.first[:label]
    assert_in_delta 45.4642, suggestions.first[:latitude]
    assert_in_delta 9.19, suggestions.first[:longitude]
  end

  test "suggestions prepends the POI name when present" do
    stub_photon([ photon_feature(name: "Osteria del Borgo") ])

    assert_equal "Osteria del Borgo, Via Roma 42, 20121 Milano, Italia",
                 Geocoding.suggestions("Osteria del Borgo").first[:label]
  end

  test "suggestions filters out countries not in the configured list" do
    stub_photon([
      photon_feature,
      photon_feature(street: "Rue de Rivoli", city: "Paris", postcode: "75001",
                     country: "France", countrycode: "FR", lat: 48.8606, lon: 2.3376)
    ])

    suggestions = Geocoding.suggestions("Rivoli")

    assert_equal 1, suggestions.length
    assert_includes suggestions.first[:label], "Milano"
  end

  test "suggestions allows all countries when the configured list is empty" do
    original = Rails.application.config.x.geocoding.country_codes
    Rails.application.config.x.geocoding.country_codes = []
    stub_photon([ photon_feature(countrycode: "FR", country: "France") ])

    assert_equal 1, Geocoding.suggestions("Rue de Rivoli").length
  ensure
    Rails.application.config.x.geocoding.country_codes = original
  end

  test "suggestions sends limit, bias and language params to photon" do
    stub_photon([])

    Geocoding.suggestions("Via Roma 42")

    assert_requested :get, PhotonStubs::PHOTON_API, times: 1 do |request|
      params = Rack::Utils.parse_query(request.uri.query)
      params["limit"] == "5" && params["lat"] == "42.5" && params["lon"] == "12.5" &&
        %w[en it].include?(params["lang"])
    end
  end

  test "suggestions caches results per query" do
    stub_photon([ photon_feature ])

    2.times { Geocoding.suggestions("Via Roma 42") }

    assert_requested :get, PhotonStubs::PHOTON_API, times: 1
  end

  test "suggestions returns empty when photon times out" do
    stub_request(:get, PhotonStubs::PHOTON_API).to_timeout

    assert_equal [], Geocoding.suggestions("Via Roma 42")
  end

  test "suggestions does not cache failures" do
    stub_request(:get, PhotonStubs::PHOTON_API).to_timeout
    assert_equal [], Geocoding.suggestions("Via Roma 42")

    stub_photon([ photon_feature ])

    assert_equal 1, Geocoding.suggestions("Via Roma 42").length
  end

  test "allowed_country? is case-insensitive and nil-safe" do
    assert Geocoding.allowed_country?("it")
    assert Geocoding.allowed_country?("IT")
    assert_not Geocoding.allowed_country?("FR")
    assert_not Geocoding.allowed_country?(nil)
  end
end
