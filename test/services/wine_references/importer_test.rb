require "test_helper"

module WineReferences
  class ImporterTest < ActiveSupport::TestCase
    HEADER = "WineID,WineName,Type,Elaborate,Grapes,Harmonize,ABV,Body,Acidity,Code,Country," \
             "RegionID,RegionName,WineryID,WineryName,Website,Vintages".freeze

    MERLOT = '100062,Origem Merlot,Red,Varietal/100%,[\'Merlot\'],"[\'Beef\', \'Lamb\', \'Pizza\']",' \
             "13.0,Full-bodied,Medium,BR,Brazil,1002,Vale dos Vinhedos,10014,Casa Valduga," \
             'http://www.casavalduga.com.br,"[2020, 2019, 2018]"'.freeze

    def import(*rows)
      Tempfile.create([ "xwines", ".csv" ]) do |file|
        file.write(([ HEADER ] + rows).join("\n"))
        file.flush
        Importer.call(file.path)
      end
    end

    test "imports a row into a wine reference with mapped attributes" do
      summary = import(MERLOT)

      assert_equal 1, summary.imported
      assert_equal 0, summary.skipped

      reference = WineReference.sole
      assert_equal "100062", reference.external_id
      assert_equal "Origem Merlot", reference.name
      assert_equal "Casa Valduga", reference.producer
      assert_equal "Vale dos Vinhedos", reference.region
      assert_equal "Brazil", reference.country
      assert_equal "Merlot", reference.grape_variety
      assert_equal "red", reference.color
      assert_equal 13.0, reference.abv.to_f
      assert_equal [ 2018, 2019, 2020 ], reference.vintages.sort
      assert_equal [ "Beef", "Lamb", "Pizza" ], reference.food_pairings
    end

    test "joins multiple grapes into a comma separated string" do
      import "101847,Dona Antonia,Dessert/Port,Assemblage/Blend," \
             '"[\'Touriga Nacional\', \'Touriga Franca\']","[\'Blue Cheese\']",20.0,Very full-bodied,' \
             'High,PT,Portugal,1031,Porto,10674,Porto Ferreira,https://example.test,"[2021, 2020]"'

      assert_equal "Touriga Nacional, Touriga Franca", WineReference.sole.grape_variety
    end

    test "maps wine types to wine colors" do
      import(
        row(id: "1", name: "A Red", type: "Red"),
        row(id: "2", name: "A White", type: "White"),
        row(id: "3", name: "A Rose", type: "Rosé"),
        row(id: "4", name: "A Sparkler", type: "Sparkling"),
        row(id: "5", name: "A Dessert", type: "Dessert"),
        row(id: "6", name: "A Port", type: "Dessert/Port"),
        row(id: "7", name: "An Oddity", type: "Orange")
      )

      colors = WineReference.order(:external_id).pluck(:color)
      assert_equal [ "red", "white", "rose", "sparkling", "dessert", "dessert", nil ], colors
      assert_empty WineReference.where.not(color: nil).where.not(color: Wine.colors.keys)
    end

    test "re-importing the same file is idempotent" do
      import(MERLOT)
      summary = import(MERLOT)

      assert_equal 1, WineReference.count
      assert_equal 1, summary.imported
    end

    test "re-importing updates changed fields" do
      import(MERLOT)
      import row(id: "100062", name: "Origem Merlot Reserva", type: "White", winery: "New Winery")

      reference = WineReference.sole
      assert_equal "Origem Merlot Reserva", reference.name
      assert_equal "white", reference.color
      assert_equal "New Winery", reference.producer
    end

    test "skips rows with a blank name or a blank id" do
      summary = import(
        row(id: "200", name: ""),
        row(id: "", name: "Nameless Id"),
        row(id: "201", name: "   ")
      )

      assert_equal 0, summary.imported
      assert_equal 3, summary.skipped
      assert_equal 0, WineReference.count
    end

    test "tolerates malformed rows without aborting the import" do
      summary = import(
        "a-line-with-no-columns",
        '300,Broken "quoting" Wine,Red,,[],[],notanumber,,,IT,Italy,,Toscana,,Cantina,,[oops]',
        MERLOT
      )

      assert_equal 2, summary.imported
      assert_equal 1, summary.skipped

      assert WineReference.exists?(external_id: "100062")
      broken = WineReference.find_by(external_id: "300")
      assert_equal 'Broken "quoting" Wine', broken.name
      assert_nil broken.abv
      assert_empty broken.vintages
    end

    test "keeps the rows parsed before an unreadable line instead of raising" do
      summary = import(MERLOT, '400,"Unterminated quote')

      assert_equal 1, summary.imported
      assert WineReference.exists?(external_id: "100062")
    end

    test "reports truncation when a structural error cuts the parse short" do
      summary = import(
        MERLOT,
        '400,"Unterminated quote',
        row(id: "500", name: "After The Break", vintages: "[2020]")
      )

      assert summary.truncated?, "expected the summary to flag the truncated run"
      assert_match(/unclosed quoted field/i, summary.error.to_s)
      assert_match(/truncated/i, summary.to_s)

      # Everything after the malformed line is lost, which is exactly why the
      # summary has to say so instead of reporting a plausible count.
      assert_equal 1, summary.imported
      assert_not WineReference.exists?(external_id: "500")
    end

    test "a clean run is not flagged as truncated" do
      summary = import(MERLOT)

      assert_not summary.truncated?
      assert_nil summary.error
      assert_no_match(/truncated/i, summary.to_s)
    end

    test "counts a repeated id once even when it spans several batches" do
      rows = Array.new(Importer::BATCH_SIZE + 100) { MERLOT }
      summary = import(*rows)

      assert_equal 1, summary.imported
      assert_equal 1, WineReference.count
    end

    test "treats a bare pandas nan in the grapes and harmonize cells as empty" do
      import row(id: "600", name: "Nan Blend", grapes: "nan", pairings: "NaN")

      reference = WineReference.sole
      assert_nil reference.grape_variety
      assert_empty reference.food_pairings
    end

    test "parses python literal lists and ignores non numeric vintages" do
      import row(id: "400", name: "N.V. Blend", vintages: '"[2021, 2020, \'N.V.\']"',
                 grapes: '"[\'Syrah\', \'Grenache\']"')

      reference = WineReference.sole
      assert_equal [ 2020, 2021 ], reference.vintages.sort
      assert_equal "Syrah, Grenache", reference.grape_variety
    end

    test "leaves optional fields blank when the source columns are empty" do
      import row(id: "500", name: "Bare Bones", type: "", grapes: "", pairings: "",
                 abv: "", country: "", region: "", winery: "", vintages: "")

      reference = WineReference.sole
      assert_nil reference.color
      assert_nil reference.abv
      assert_nil reference.producer
      assert_empty reference.vintages
      assert_empty reference.food_pairings
    end

    test "imports the committed sample dataset" do
      summary = Importer.call(Importer::DEFAULT_PATH)

      assert_operator summary.imported, :>, 50
      assert_equal summary.imported, WineReference.count
      assert WineReference.where(color: "dessert").exists?
      assert WineReference.where(color: "rose").exists?
    end

    private

    def row(id:, name:, type: "Red", grapes: "['Merlot']", pairings: "['Beef']", abv: "13.0",
            country: "Italy", region: "Toscana", winery: "Cantina Test", vintages: '"[2020, 2019]"')
      [ id, name, type, "Varietal/100%", grapes, pairings, abv, "Full-bodied", "Medium", "IT",
        country, "1002", region, "10014", winery, "https://example.test", vintages ].join(",")
    end
  end
end
