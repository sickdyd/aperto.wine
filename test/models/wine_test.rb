require "test_helper"

class WineTest < ActiveSupport::TestCase
  def valid_attributes
    {
      restaurant: restaurants(:osteria),
      name: "Chianti Classico",
      color: :red,
      bottle_size_ml: 750,
      available_glasses: 5,
      price_75ml_cents: 1200,
      price_100ml_cents: 1500,
      price_125ml_cents: 1800,
      price_150ml_cents: 2100
    }
  end

  # --- Validations ---

  test "creates a valid wine" do
    wine = Wine.new(valid_attributes)
    assert wine.valid?
  end

  test "requires name" do
    wine = Wine.new(valid_attributes.merge(name: ""))
    assert_not wine.valid?
    assert_includes wine.errors[:name], "can't be blank"
  end

  test "requires bottle_size_ml greater than 0" do
    wine = Wine.new(valid_attributes.merge(bottle_size_ml: 0))
    assert_not wine.valid?
    assert_includes wine.errors[:bottle_size_ml], "must be greater than 0"
  end

  test "rejects negative bottle_size_ml" do
    wine = Wine.new(valid_attributes.merge(bottle_size_ml: -1))
    assert_not wine.valid?
  end

  test "requires available_glasses >= 0" do
    wine = Wine.new(valid_attributes.merge(available_glasses: -1))
    assert_not wine.valid?
    assert_includes wine.errors[:available_glasses], "must be greater than or equal to 0"
  end

  test "allows available_glasses of zero" do
    wine = Wine.new(valid_attributes.merge(available_glasses: 0))
    assert wine.valid?
  end

  test "requires restaurant" do
    wine = Wine.new(valid_attributes.merge(restaurant: nil))
    assert_not wine.valid?
  end

  # --- Enums ---

  test "color enum values" do
    assert_equal 0, Wine.colors[:red]
    assert_equal 1, Wine.colors[:white]
    assert_equal 2, Wine.colors[:rose]
    assert_equal 3, Wine.colors[:sparkling]
    assert_equal 4, Wine.colors[:dessert]
  end

  test "color predicate methods work" do
    wine = Wine.new(valid_attributes.merge(color: :white))
    assert wine.white?
    assert_not wine.red?

    wine.color = :sparkling
    assert wine.sparkling?
  end

  # --- GLASS_SIZES constant ---

  test "GLASS_SIZES contains expected values" do
    assert_equal [ 75, 100, 125, 150 ], Wine::GLASS_SIZES
  end

  # --- Scopes ---

  test "active scope returns only active wines" do
    active = Wine.active
    assert_includes active, wines(:barolo)
    assert_includes active, wines(:gavi)
  end

  test "active scope excludes inactive wines" do
    wine = wines(:barolo)
    wine.update!(active: false)
    assert_not_includes Wine.active, wine
  end

  test "by_position scope orders by color then position then name" do
    result = restaurants(:osteria).wines.by_position
    assert result.is_a?(ActiveRecord::Relation)
    # Verify ordering — red (0) should come before white (1)
    red_index   = result.to_a.index(wines(:barolo))
    white_index = result.to_a.index(wines(:gavi))
    assert red_index < white_index
  end

  # --- suggested_glasses ---

  test "suggested_glasses returns floor division of bottle_size by glass_size" do
    wine = wines(:barolo) # bottle_size_ml: 750
    assert_equal 10, wine.suggested_glasses(75)
    assert_equal 7,  wine.suggested_glasses(100)
    assert_equal 6,  wine.suggested_glasses(125)
    assert_equal 5,  wine.suggested_glasses(150)
  end

  test "suggested_glasses returns 0 for zero glass_size" do
    wine = wines(:barolo)
    assert_equal 0, wine.suggested_glasses(0)
  end

  test "suggested_glasses floors the result" do
    wine = Wine.new(valid_attributes.merge(bottle_size_ml: 700))
    assert_equal 9,  wine.suggested_glasses(75)   # 700/75 = 9.33 -> 9
    assert_equal 5,  wine.suggested_glasses(125)  # 700/125 = 5.6 -> 5
  end

  # --- price_for_glass ---

  test "price_for_glass returns correct price for each size" do
    wine = wines(:barolo)
    assert_equal wine.price_75ml_cents,  wine.price_for_glass(75)
    assert_equal wine.price_100ml_cents, wine.price_for_glass(100)
    assert_equal wine.price_125ml_cents, wine.price_for_glass(125)
    assert_equal wine.price_150ml_cents, wine.price_for_glass(150)
  end

  test "price_for_glass returns nil for unknown size" do
    wine = wines(:barolo)
    assert_nil wine.price_for_glass(200)
  end

  # --- available? ---

  test "available? returns true when active and has glasses" do
    wine = wines(:barolo) # active: true, available_glasses: 10
    assert wine.available?
  end

  test "available? returns false when active but zero glasses" do
    wine = wines(:sold_out_wine) # active: true, available_glasses: 0
    assert_not wine.available?
  end

  test "available? returns false when inactive even with glasses" do
    wine = wines(:barolo)
    wine.update!(active: false)
    assert_not wine.available?
  end

  test "available? returns false when both inactive and zero glasses" do
    wine = wines(:sold_out_wine)
    wine.update!(active: false)
    assert_not wine.available?
  end

  # --- abv ---

  test "allows nil abv" do
    assert Wine.new(valid_attributes.merge(abv: nil)).valid?
  end

  test "allows abv within range" do
    assert Wine.new(valid_attributes.merge(abv: 13.5)).valid?
  end

  test "rejects negative abv" do
    assert_not Wine.new(valid_attributes.merge(abv: -1)).valid?
  end

  test "rejects abv above 100" do
    assert_not Wine.new(valid_attributes.merge(abv: 100.1)).valid?
  end

  test "allows abv of exactly 100 and persists without overflow" do
    wine = Wine.new(valid_attributes.merge(abv: 100))
    assert wine.valid?
    assert_nothing_raised { wine.save! }
    assert_equal 100, wine.reload.abv.to_i
  end

  # --- tasting profile ---

  test "allows nil tasting attributes" do
    wine = Wine.new(valid_attributes.merge(tannins: nil, acidity: nil, sweetness: nil, body: nil))
    assert wine.valid?
  end

  test "allows tasting attributes within 0..5" do
    wine = Wine.new(valid_attributes.merge(tannins: 0, acidity: 3, sweetness: 5, body: 4))
    assert wine.valid?
  end

  test "rejects tasting attribute above 5" do
    wine = Wine.new(valid_attributes.merge(tannins: 6))
    assert_not wine.valid?
    assert_includes wine.errors[:tannins], "must be in 0..5"
  end

  test "rejects tasting attribute below 0" do
    assert_not Wine.new(valid_attributes.merge(body: -1)).valid?
  end

  test "TASTING_ATTRIBUTES lists the four profile columns" do
    assert_equal %i[tannins acidity sweetness body], Wine::TASTING_ATTRIBUTES
  end

  # --- certification labels ---

  test "certification labels default to false" do
    wine = Wine.create!(valid_attributes)
    Wine::CERTIFICATION_LABELS.each do |label|
      assert_not wine.public_send(label), "expected #{label} to default to false"
    end
  end

  # --- array fields ---

  test "aromas and food_pairings default to empty arrays" do
    wine = Wine.create!(valid_attributes)
    assert_equal [], wine.aromas
    assert_equal [], wine.food_pairings
  end

  test "persists aromas and food_pairings arrays" do
    wine = Wine.create!(valid_attributes.merge(
      aromas: [ "cherry", "leather" ],
      food_pairings: [ "Braised beef", "Aged cheese" ]
    ))
    assert_equal [ "cherry", "leather" ], wine.reload.aromas
    assert_equal [ "Braised beef", "Aged cheese" ], wine.food_pairings
  end

  # --- featured scope ---

  test "featured scope returns only featured wines" do
    wine = wines(:barolo)
    wine.update!(featured: true)
    assert_includes Wine.featured, wine
    assert_not_includes Wine.featured, wines(:gavi)
  end

  # --- image_url ---

  test "allows blank image_url" do
    assert Wine.new(valid_attributes.merge(image_url: nil)).valid?
  end

  test "allows http(s) image_url" do
    assert Wine.new(valid_attributes.merge(image_url: "https://cdn.example.com/a.jpg")).valid?
  end

  test "rejects non-http image_url scheme" do
    wine = Wine.new(valid_attributes.merge(image_url: "javascript:alert(1)"))
    assert_not wine.valid?
    assert_includes wine.errors[:image_url], "must be an http(s) URL"
  end

  test "rejects overly long image_url" do
    wine = Wine.new(valid_attributes.merge(image_url: "https://e.com/#{'a' * 2048}"))
    assert_not wine.valid?
  end

  # --- length caps ---

  test "rejects too many aromas" do
    wine = Wine.new(valid_attributes.merge(aromas: Array.new(21) { |i| "aroma#{i}" }))
    assert_not wine.valid?
  end

  test "rejects too long short_description" do
    assert_not Wine.new(valid_attributes.merge(short_description: "x" * 501)).valid?
  end

  # --- label image ---

  test "can attach a valid label image" do
    wine = Wine.create!(valid_attributes)
    wine.label_image.attach(
      io: StringIO.new("fake-image-bytes"),
      filename: "label.png",
      content_type: "image/png"
    )
    assert wine.label_image.attached?
    assert wine.valid?
  end

  test "rejects a label image with a disallowed content type" do
    wine = Wine.create!(valid_attributes)
    wine.label_image.attach(
      io: StringIO.new("not-an-image"),
      filename: "evil.txt",
      content_type: "text/plain"
    )
    assert_not wine.valid?
    assert wine.errors[:label_image].any?
  end

  # --- Associations ---

  test "belongs to restaurant" do
    assert_equal restaurants(:osteria), wines(:barolo).restaurant
  end

  test "has many wine_bottles" do
    assert_respond_to wines(:barolo), :wine_bottles
    assert_includes wines(:barolo).wine_bottles, wine_bottles(:sealed_barolo)
  end

  test "destroys dependent wine_bottles when deleted" do
    wine = Wine.create!(valid_attributes)
    wine.wine_bottles.create!(status: :sealed, glasses_remaining: 10)
    assert_difference "WineBottle.count", -1 do
      wine.destroy
    end
  end
end
