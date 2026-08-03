require "test_helper"

module WineReferences
  class PythonListTest < ActiveSupport::TestCase
    test "parses a quoted python literal list" do
      assert_equal [ "Merlot", "Syrah" ], PythonList.parse("['Merlot', 'Syrah']")
      assert_equal [ "Beef", "Blue Cheese" ], PythonList.parse('["Beef", "Blue Cheese"]')
    end

    test "returns an empty list for blank input" do
      assert_equal [], PythonList.parse(nil)
      assert_equal [], PythonList.parse("")
      assert_equal [], PythonList.parse("   ")
      assert_equal [], PythonList.parse("[]")
    end

    # pandas `to_csv()` writes a missing value as a bare `nan`, so the full
    # dataset contains cells that carry no list at all.
    test "treats a bare pandas null token as an empty list" do
      [ "nan", "NaN", "NAN", " nan ", "None", "none", "NONE" ].each do |token|
        assert_equal [], PythonList.parse(token), "expected #{token.inspect} to parse as empty"
      end
    end

    test "keeps a null token that is a genuine list element" do
      assert_equal [ "nan" ], PythonList.parse("['nan']")
      assert_equal [ "Merlot", "None" ], PythonList.parse("['Merlot', 'None']")
    end

    test "integers ignores non numeric elements and sorts uniquely" do
      assert_equal [ 2020, 2021 ], PythonList.integers("[2021, 2020, 'N.V.', 2021]")
      assert_equal [], PythonList.integers("nan")
    end
  end
end
