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

  private

  def valid_attributes_for_wine
    { restaurant: restaurants(:osteria), name: "Chianti Classico", color: :red,
      bottle_size_ml: 750, available_glasses: 5 }
  end
end
