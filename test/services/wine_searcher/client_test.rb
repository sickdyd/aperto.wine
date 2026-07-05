require "test_helper"
require "webmock/minitest"

module WineSearcher
  class ClientTest < ActiveSupport::TestCase
    API_URL = "https://api.example.test/wine-check"

    setup do
      ENV["WINE_SEARCHER_API_KEY"] = "test-key"
      ENV["WINE_SEARCHER_API_URL"] = API_URL
    end

    teardown do
      ENV.delete("WINE_SEARCHER_API_KEY")
      ENV.delete("WINE_SEARCHER_API_URL")
    end

    test "configured? is false without a key" do
      ENV.delete("WINE_SEARCHER_API_KEY")
      assert_not Client.new.configured?
    end

    test "configured? is true with key and url" do
      assert Client.new.configured?
    end

    test "search returns [] without calling the API when unconfigured" do
      ENV.delete("WINE_SEARCHER_API_KEY")
      results = Client.new.search("barolo")
      assert_equal [], results
      assert_not_requested :get, /api\.example\.test/
    end

    test "search returns [] for queries shorter than 3 chars without calling the API" do
      assert_equal [], Client.new.search("ba")
      assert_not_requested :get, /api\.example\.test/
    end

    test "search maps a wine payload to Result structs" do
      stub_request(:get, API_URL)
        .with(query: hash_including("api_key" => "test-key", "winename" => "Haut Brion"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            "wines" => [
              {
                "wine-name" => "Chateau Haut-Brion",
                "producer" => "Chateau Haut-Brion",
                "region" => "Pessac-Leognan",
                "grape" => "Cabernet Sauvignon blend",
                "vintage" => "1995",
                "wine-type" => "Red"
              }
            ]
          }.to_json
        )

      results = Client.new.search("Haut Brion")

      assert_equal 1, results.size
      result = results.first
      assert_equal "Chateau Haut-Brion", result.name
      assert_equal "Chateau Haut-Brion", result.producer
      assert_equal "Pessac-Leognan", result.region
      assert_equal "Cabernet Sauvignon blend", result.grape_variety
      assert_equal 1995, result.vintage_year
      assert_equal "red", result.color
    end

    test "search tolerates a single wine object instead of an array" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "gavi"))
        .to_return(status: 200, body: { "wine" => { "wine-name" => "Gavi di Gavi", "wine-type" => "White" } }.to_json)

      results = Client.new.search("gavi")
      assert_equal [ "Gavi di Gavi" ], results.map(&:name)
      assert_equal "white", results.first.color
    end

    test "search skips entries without a wine name and drops out-of-range vintages" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "mystery"))
        .to_return(status: 200, body: {
          "wines" => [
            { "region" => "Nowhere" },
            { "wine-name" => "Old One", "vintage" => "1400" },
            { "wine-name" => "Bad Year", "vintage" => "next year" }
          ]
        }.to_json)

      results = Client.new.search("mystery")
      assert_equal [ "Old One", "Bad Year" ], results.map(&:name)
      assert_nil results[0].vintage_year
      assert_nil results[1].vintage_year
    end

    test "color derivation handles all supported styles and unknown ones" do
      client = Client.new
      {
        "Red" => "red", "White" => "white", "Rose" => "rose", "Rosé" => "rose",
        "Sparkling" => "sparkling", "Champagne" => "sparkling",
        "Dessert" => "dessert", "Sweet white" => "dessert", "Port/Fortified" => "dessert",
        "Orange" => nil, nil => nil
      }.each do |style, expected|
        result = client.send(:derive_color, style)
        if expected.nil?
          assert_nil result, "style #{style.inspect}"
        else
          assert_equal expected, result, "style #{style.inspect}"
        end
      end
    end

    test "search returns [] on non-200 responses" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo"))
        .to_return(status: 429, body: "quota exceeded")

      assert_equal [], Client.new.search("barolo")
    end

    test "search returns [] on timeouts" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo")).to_timeout

      assert_equal [], Client.new.search("barolo")
    end

    test "search returns [] on malformed JSON" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo"))
        .to_return(status: 200, body: "<not json>")

      assert_equal [], Client.new.search("barolo")
    end
  end
end
