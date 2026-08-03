require "test_helper"

module WineReferences
  class LookupTest < ActiveSupport::TestCase
    RESULT_KEYS = %i[name producer region grape_variety vintage_year color].freeze

    def create_reference(name:, external_id: nil, **attributes)
      WineReference.create!(
        external_id: external_id || "ref-#{SecureRandom.hex(4)}",
        name: name,
        **attributes
      )
    end

    def search(query)
      Lookup.new.search(query)
    end

    test "returns an empty array for queries shorter than three characters" do
      create_reference(name: "Barolo Riserva")

      assert_equal [], search("ba")
      assert_equal [], search("")
      assert_equal [], search(nil)
      assert_equal [], search("  b  ")
    end

    test "matches a substring of the name case insensitively" do
      create_reference(name: "Barolo Riserva")

      assert_equal [ "Barolo Riserva" ], search("rolo").map(&:name)
      assert_equal [ "Barolo Riserva" ], search("BAROLO").map(&:name)
    end

    test "matches a substring of the producer" do
      create_reference(name: "Sassicaia", producer: "Tenuta San Guido")

      assert_equal [ "Sassicaia" ], search("san guido").map(&:name)
    end

    test "ignores references that match neither name nor producer" do
      create_reference(name: "Barolo Riserva", producer: "Conterno", region: "Piemonte")

      assert_equal [], search("piemonte")
    end

    test "ranks exact then prefix matches on the name above other matches" do
      create_reference(name: "Vintage Barolo Selection")
      create_reference(name: "Barolo Riserva")
      create_reference(name: "Barolo")

      assert_equal [ "Barolo", "Barolo Riserva", "Vintage Barolo Selection" ], search("barolo").map(&:name)
    end

    test "caps the results at eight" do
      12.times { |i| create_reference(name: "Barolo Number #{i}") }

      assert_equal 8, search("barolo").size
    end

    test "caps the results at eight across all rank tiers" do
      create_reference(name: "Barolo")
      4.times { |i| create_reference(name: "Barolo Prefix #{i}") }
      6.times { |i| create_reference(name: "Reserva Barolo #{i}") }

      names = search("barolo").map(&:name)

      assert_equal 8, names.size
      assert_equal "Barolo", names.first
      assert_equal 4, names.count { |name| name.start_with?("Barolo Prefix") }
    end

    test "returns a reference once even when it matches several rank tiers" do
      create_reference(name: "Barolo", producer: "Barolo Estate")
      create_reference(name: "Barolo Riserva", producer: "Barolo Estate")

      assert_equal [ "Barolo", "Barolo Riserva" ], search("barolo").map(&:name)
    end

    test "vintage_year is the most recent vintage and nil when there are none" do
      create_reference(name: "Barolo Riserva", vintages: [ 2012, 2019, 2015 ])
      create_reference(name: "Barolo Nonvintage")

      results = search("barolo").index_by(&:name)
      assert_equal 2019, results["Barolo Riserva"].vintage_year
      assert_nil results["Barolo Nonvintage"].vintage_year
    end

    test "treats LIKE metacharacters in the query literally" do
      create_reference(name: "Cuvee 50% Merlot")
      create_reference(name: "Cuvee Anything Merlot")
      create_reference(name: "Rosso_Conero")
      create_reference(name: "RossoXConero")

      assert_equal [ "Cuvee 50% Merlot" ], search("50% Merlot").map(&:name)
      assert_equal [ "Rosso_Conero" ], search("sso_Con").map(&:name)
    end

    test "treats a backslash in the query literally" do
      create_reference(name: 'Domaine A\\B')
      create_reference(name: "Domaine AB")

      assert_equal [ 'Domaine A\\B' ], search('ne A\\B').map(&:name)
    end

    test "to_h exposes exactly the keys the autofill controller consumes" do
      create_reference(name: "Sassicaia", producer: "Tenuta San Guido", region: "Toscana",
                       grape_variety: "Cabernet Sauvignon", color: "red", vintages: [ 2019 ],
                       country: "Italy", abv: 13.5)

      payload = search("sassicaia").first.to_h

      assert_equal RESULT_KEYS.sort, payload.keys.sort
      assert_equal(
        { name: "Sassicaia", producer: "Tenuta San Guido", region: "Toscana",
          grape_variety: "Cabernet Sauvignon", vintage_year: 2019, color: "red" },
        payload
      )
    end
  end
end
