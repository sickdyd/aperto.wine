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

  # Password and Email are grammatically feminine in Italian. rails-i18n itself
  # already treats password as feminine (it ships `password_too_long: "è troppo
  # lunga"`), and Email (< posta elettronica) is feminine per the Accademia della
  # Crusca. The gem's generic halves are masculine ("lasciato", "corto",
  # "valido"), so each feminine attribute whose validation can fire carries an
  # override that agrees in gender. The English side mirrors the gem and is
  # drift-guarded below.
  test "password too_short error agrees in gender under :it" do
    user = User.new(valid_attributes_for_user.merge(password: "short", password_confirmation: "short"))
    I18n.with_locale(:it) do
      user.valid?
      message = user.errors.where(:password, :too_short).first&.message
      assert message, "expected a password too_short error, got: #{user.errors.details.inspect}"
      assert_match(/è troppo corta/, message, "feminine 'password' should read 'corta'")
      assert_no_match(/è troppo corto\b/, message, "masculine 'corto' leaked for feminine 'password'")
    end
  end

  test "password blank error agrees in gender under :it" do
    user = User.new(valid_attributes_for_user.merge(password: "", password_confirmation: ""))
    I18n.with_locale(:it) do
      user.valid?
      message = user.errors.where(:password, :blank).first&.message
      assert message, "expected a password blank error, got: #{user.errors.details.inspect}"
      assert_equal "non può essere lasciata in bianco", message
    end
  end

  test "email blank error agrees in gender under :it" do
    user = User.new(valid_attributes_for_user.merge(email: ""))
    I18n.with_locale(:it) do
      user.valid?
      message = user.errors.where(:email, :blank).first&.message
      assert message, "expected an email blank error, got: #{user.errors.details.inspect}"
      assert_equal "non può essere lasciata in bianco", message
    end
  end

  test "email invalid error agrees in gender under :it" do
    user = User.new(valid_attributes_for_user.merge(email: "not-an-email"))
    I18n.with_locale(:it) do
      user.valid?
      message = user.errors.where(:email, :invalid).first&.message
      assert message, "expected an email invalid error, got: #{user.errors.details.inspect}"
      assert_equal "non è valida", message
    end
  end

  test "password_confirmation mismatch names the field in Italian under :it" do
    user = User.new(valid_attributes_for_user.merge(password: "password123", password_confirmation: "different123"))
    I18n.with_locale(:it) do
      user.valid?
      assert_includes user.errors.full_messages, "Conferma password non coincide con Password"
    end
  end

  test "password_confirmation mismatch names the field in English under :en" do
    user = User.new(valid_attributes_for_user.merge(password: "password123", password_confirmation: "different123"))
    user.valid?
    assert_includes user.errors.full_messages, "Password confirmation doesn't match Password"
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
    "activerecord.errors.models.wine.attributes.sweetness.in" => "errors.messages.in",
    "activerecord.errors.models.user.attributes.password.too_short" => "errors.messages.too_short",
    "activerecord.errors.models.user.attributes.password.blank" => "errors.messages.blank",
    "activerecord.errors.models.user.attributes.email.blank" => "errors.messages.blank",
    "activerecord.errors.models.user.attributes.email.invalid" => "errors.messages.invalid"
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

  def valid_attributes_for_user
    { email: "taster-#{SecureRandom.hex(4)}@example.com", name: "Taster",
      role: :customer, password: "password123", password_confirmation: "password123" }
  end
end
