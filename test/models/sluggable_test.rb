require "test_helper"

# Slug generation is shared by Restaurant and WineList through Sluggable, but
# the two differ in the ways that matter for public URLs: a restaurant slug is
# globally unique and frozen after creation (printed QR codes point at it),
# while a wine list slug is unique only within its restaurant and follows the
# list's name.
class SluggableTest < ActiveSupport::TestCase
  # --- Restaurant: generation ---

  def restaurant_attributes(overrides = {})
    {
      user: users(:owner),
      name: "La Trattoria",
      address: "Via Garibaldi 10, Torino"
    }.merge(overrides)
  end

  test "derives a restaurant slug from the name" do
    restaurant = Restaurant.create!(restaurant_attributes(name: "Osteria Da Gino"))
    assert_equal "osteria-da-gino", restaurant.slug
  end

  test "strips accents and punctuation from a generated restaurant slug" do
    restaurant = Restaurant.create!(restaurant_attributes(name: "Caffè dell'Orso & Co."))
    assert_equal "caffe-dell-orso-co", restaurant.slug
  end

  test "suffixes a restaurant slug that is already taken" do
    first = Restaurant.create!(restaurant_attributes(name: "Duplicate Name"))
    second = Restaurant.create!(restaurant_attributes(name: "Duplicate Name"))

    assert_equal "duplicate-name", first.slug
    assert_equal "duplicate-name-2", second.slug
  end

  test "falls back to a name-independent restaurant slug when the name yields nothing" do
    restaurant = Restaurant.create!(restaurant_attributes(name: "☆☆☆"))

    assert_match(/\Arestaurant-[a-z0-9]+\z/, restaurant.slug)
  end

  test "keeps the restaurant slug when the name changes so printed QR codes stay valid" do
    restaurant = Restaurant.create!(restaurant_attributes(name: "Original Name"))

    restaurant.update!(name: "Renamed Entirely")

    assert_equal "original-name", restaurant.slug
  end

  # --- Long names ---
  #
  # Restaurant names carry no length limit, so a generated slug has to be
  # truncated. Truncation is where a slug most easily comes out invalid:
  # cutting mid-word leaves a trailing hyphen, and appending a collision
  # suffix can push it back over the limit.

  test "truncates a long generated restaurant slug to the maximum length" do
    restaurant = Restaurant.create!(restaurant_attributes(name: "Osteria " * 40))

    assert_operator restaurant.slug.length, :<=, Sluggable::MAX_LENGTH
    assert_match Sluggable::SLUG_FORMAT, restaurant.slug
  end

  test "a truncated slug never ends in a hyphen" do
    # "abc abc …" parameterizes to repeating four-character "abc-" units, so
    # a naive cut at 100 characters lands exactly on a hyphen — which
    # SLUG_FORMAT rejects. Guard the premise so this cannot pass vacuously if
    # MAX_LENGTH changes.
    name = "abc " * 40
    assert name.parameterize.first(Sluggable::MAX_LENGTH).end_with?("-"),
           "fixture no longer exercises a hyphen-boundary truncation"

    restaurant = Restaurant.create!(restaurant_attributes(name: name))

    assert_not restaurant.slug.end_with?("-")
    assert_match Sluggable::SLUG_FORMAT, restaurant.slug
  end

  test "a collision suffix keeps a long slug inside the length limit" do
    name = "Osteria " * 40
    first = Restaurant.create!(restaurant_attributes(name: name))
    second = Restaurant.create!(restaurant_attributes(name: name))

    assert_not_equal first.slug, second.slug
    assert_operator second.slug.length, :<=, Sluggable::MAX_LENGTH
    assert_match Sluggable::SLUG_FORMAT, second.slug
    assert second.slug.end_with?("-2")
  end

  # --- Restaurant: owner-supplied slugs ---

  test "accepts an explicit restaurant slug" do
    restaurant = Restaurant.create!(restaurant_attributes(slug: "my-own-url"))
    assert_equal "my-own-url", restaurant.slug
  end

  test "normalizes an explicit restaurant slug" do
    restaurant = Restaurant.create!(restaurant_attributes(slug: "  My Own URL  "))
    assert_equal "my-own-url", restaurant.slug
  end

  test "regenerates the restaurant slug when it is blanked out" do
    restaurant = Restaurant.create!(restaurant_attributes(name: "Blank Me"))

    restaurant.update!(slug: "")

    assert_equal "blank-me", restaurant.slug
  end

  test "rejects a restaurant slug that collides with another restaurant" do
    Restaurant.create!(restaurant_attributes(slug: "taken-slug"))
    other = Restaurant.new(restaurant_attributes(slug: "taken-slug"))

    assert_not other.valid?
    assert other.errors.of_kind?(:slug, :taken)
  end

  test "rejects a restaurant slug that shadows a reserved path segment" do
    Restaurant::RESERVED_SLUGS.each do |reserved|
      restaurant = Restaurant.new(restaurant_attributes(slug: reserved))

      assert_not restaurant.valid?, "expected #{reserved.inspect} to be rejected"
      assert restaurant.errors.of_kind?(:slug, :exclusion)
    end
  end

  test "never generates a reserved restaurant slug" do
    restaurant = Restaurant.create!(restaurant_attributes(name: "Menu"))

    assert_not_includes Restaurant::RESERVED_SLUGS, restaurant.slug
    assert_equal "menu-2", restaurant.slug
  end

  # --- WineList ---

  test "derives a wine list slug from the name" do
    list = restaurants(:osteria).wine_lists.create!(name: "Carta dei Rossi")
    assert_equal "carta-dei-rossi", list.slug
  end

  test "follows the name when a wine list is renamed" do
    list = restaurants(:osteria).wine_lists.create!(name: "Winter Card")

    list.update!(name: "Spring Card")

    assert_equal "spring-card", list.slug
  end

  test "suffixes a wine list slug taken within the same restaurant" do
    osteria = restaurants(:osteria)
    first = osteria.wine_lists.create!(name: "Same Name")
    second = osteria.wine_lists.create!(name: "Same Name")

    assert_equal "same-name", first.slug
    assert_equal "same-name-2", second.slug
  end

  test "allows the same wine list slug in different restaurants" do
    a = restaurants(:osteria).wine_lists.create!(name: "House Card")
    b = restaurants(:trattoria).wine_lists.create!(name: "House Card")

    assert_equal a.slug, b.slug
  end

  test "rejects a wine list slug that collides within its restaurant" do
    osteria = restaurants(:osteria)
    osteria.wine_lists.create!(name: "Taken Card")
    other = osteria.wine_lists.build(name: "Other", slug: "taken-card")

    assert_not other.valid?
    assert other.errors.of_kind?(:slug, :taken)
  end
end
