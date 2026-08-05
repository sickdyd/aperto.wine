require "test_helper"

# The two custom validation messages that used to be hardcoded English string
# literals in the models (Wine#image_url format, WineListItem same-restaurant
# rule) now live in the locale files and are referenced by symbol. Guard both
# ends: the English wording is unchanged under :en (so the existing model tests
# keep passing) and it is fully Italian under :it.
class ItalianValidationMessagesTest < ActiveSupport::TestCase
  test "wine image_url message is Italian under :it" do
    wine = Wine.new(name: "X", restaurant: restaurants(:osteria),
                    bottle_size_ml: 750, available_glasses: 0,
                    image_url: "javascript:alert(1)")
    I18n.with_locale(:it) do
      wine.valid?
      assert_includes wine.errors[:image_url], "deve essere un URL http(s)"
    end
  end

  test "wine image_url message stays English under :en" do
    wine = Wine.new(valid_attributes_for_wine.merge(image_url: "javascript:alert(1)"))
    wine.valid?
    assert_includes wine.errors[:image_url], "must be an http(s) URL"
  end

  test "wine list item same-restaurant message is Italian under :it" do
    item = WineListItem.new(wine_list: wine_lists(:trattoria_list), wine: wines(:barolo))
    I18n.with_locale(:it) do
      item.valid?
      assert_includes item.errors[:wine], "deve appartenere allo stesso ristorante della lista"
    end
  end

  test "wine list item same-restaurant message stays English under :en" do
    item = WineListItem.new(wine_list: wine_lists(:trattoria_list), wine: wines(:barolo))
    item.valid?
    assert_includes item.errors[:wine], "must belong to the same restaurant as the list"
  end

  # Rails composes "%{attribute} %{message}", and rails-i18n's Italian message
  # halves are masculine singular (`too_long: "è troppo lungo …"`). Several
  # attributes are grammatically feminine, so without a per-attribute override
  # they read as broken Italian ("Stagione è troppo lungo") to a native speaker
  # — worse than an obviously-untranslated string. Each feminine attribute whose
  # validation can actually fire gets a `too_long` override agreeing in gender.
  FEMININE_TOO_LONG_CASES = {
    "Descrizione breve" => -> { Wine.new(valid_attributes_for_wine.merge(short_description: "a" * 501)) },
    "Stagione" => -> { WineList.new(restaurant: restaurants(:osteria), name: "Estate", season: "a" * 51) },
    "Sala" => -> { RestaurantTable.new(restaurant: restaurants(:osteria), name: "1", area: "a" * 101) }
  }.freeze

  FEMININE_TOO_LONG_CASES.each do |label, build|
    test "#{label} too_long error agrees in gender under :it" do
      record = instance_exec(&build)
      I18n.with_locale(:it) do
        record.valid?
        message = record.errors.full_messages.find { |m| m.start_with?(label) }
        assert message, "expected a #{label} error, got: #{record.errors.full_messages.inspect}"
        assert_match(/è troppo lunga/, message, "feminine attribute should read 'lunga'")
        assert_no_match(/è troppo lungo\b/, message, "masculine 'lungo' leaked for a feminine attribute")
      end
    end
  end

  # The numericality `in:` range check on the tasting attributes composes
  # "deve essere uno tra %{count}" — masculine, agreeing with an implied "un
  # valore". Acidità and Dolcezza are feminine and read wrong; Tannini and Corpo
  # are masculine and must be left alone (the guard below asserts both sides so a
  # future blanket override can't over-correct them).
  FEMININE_IN_RANGE_ATTRS = { "Acidità" => :acidity, "Dolcezza" => :sweetness }.freeze
  MASCULINE_IN_RANGE_ATTRS = { "Tannini" => :tannins, "Corpo" => :body }.freeze

  FEMININE_IN_RANGE_ATTRS.each do |label, attr|
    test "#{label} range error agrees in gender under :it" do
      wine = Wine.new(valid_attributes_for_wine.merge(attr => 9))
      I18n.with_locale(:it) do
        wine.valid?
        message = wine.errors.full_messages.find { |m| m.start_with?(label) }
        assert message, "expected a #{label} error, got: #{wine.errors.full_messages.inspect}"
        assert_match(/deve essere una tra/, message, "feminine attribute should read 'una tra'")
        assert_no_match(/deve essere uno tra/, message, "masculine 'uno tra' leaked for a feminine attribute")
      end
    end
  end

  MASCULINE_IN_RANGE_ATTRS.each do |label, attr|
    test "#{label} range error stays masculine under :it" do
      wine = Wine.new(valid_attributes_for_wine.merge(attr => 9))
      I18n.with_locale(:it) do
        wine.valid?
        message = wine.errors.full_messages.find { |m| m.start_with?(label) }
        assert message, "expected a #{label} error, got: #{wine.errors.full_messages.inspect}"
        assert_match(/deve essere uno tra/, message, "masculine attribute should keep 'uno tra'")
      end
    end
  end

  # Drift guard for the English side of the too_long/in overrides above.
  #
  # We keep en.yml and it.yml at literal key parity because the user asked for
  # the two files to stay consistent (and i18n-tasks enforces it). For validation
  # errors the English keys are redundant, not load-bearing: ActiveModel passes
  # the error-key chain as symbol defaults, which I18n exhausts within :en —
  # reaching the gem's English errors.messages.* — before the :it fallback, so
  # English renders in English even without them. That redundancy is exactly why
  # this guard exists: the English values duplicate rails-i18n's generic defaults,
  # which would drift silently if the gem reworded. This asserts each English
  # override still equals the generic message it mirrors (errors.messages.*, owned
  # by rails-i18n and not shadowed by this app), read from the loaded locale data
  # at runtime. If it fails, the gem changed its wording: update the en.yml copy —
  # and re-derive the it.yml gender form from the new wording — rather than
  # deleting this guard.
  ENGLISH_GEM_MIRRORED_OVERRIDES = {
    "activerecord.errors.models.wine.attributes.short_description.too_long" => "errors.messages.too_long",
    "activerecord.errors.models.wine_list.attributes.season.too_long" => "errors.messages.too_long",
    "activerecord.errors.models.restaurant_table.attributes.area.too_long" => "errors.messages.too_long",
    "activerecord.errors.models.wine.attributes.acidity.in" => "errors.messages.in",
    "activerecord.errors.models.wine.attributes.sweetness.in" => "errors.messages.in"
  }.freeze

  ENGLISH_GEM_MIRRORED_OVERRIDES.each do |override_key, gem_key|
    test "English #{override_key} still matches the rails-i18n default #{gem_key}" do
      I18n.with_locale(:en) do
        assert_equal I18n.t(gem_key), I18n.t(override_key),
          "en.yml froze the rails-i18n wording for '#{gem_key}' and the gem has " \
          "since reworded it. Update the English copy under '#{override_key}' to " \
          "match (and re-derive the it.yml gender form), then this guard passes."
      end
    end
  end

  private

  def valid_attributes_for_wine
    { restaurant: restaurants(:osteria), name: "Chianti Classico", color: :red,
      bottle_size_ml: 750, available_glasses: 5 }
  end
end
