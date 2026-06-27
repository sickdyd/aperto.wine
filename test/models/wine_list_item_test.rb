require "test_helper"

class WineListItemTest < ActiveSupport::TestCase
  def valid_attributes
    { wine_list: wine_lists(:winter), wine: wines(:barolo) }
  end

  # --- Validations ---

  test "creates a valid item" do
    assert WineListItem.new(valid_attributes).valid?
  end

  test "requires wine_list" do
    assert_not WineListItem.new(valid_attributes.merge(wine_list: nil)).valid?
  end

  test "requires wine" do
    assert_not WineListItem.new(valid_attributes.merge(wine: nil)).valid?
  end

  test "defaults position to 0" do
    item = WineListItem.create!(valid_attributes)
    assert_equal 0, item.position
  end

  # --- Uniqueness ---

  test "rejects the same wine twice on one list" do
    dup = WineListItem.new(wine_list: wine_lists(:summer), wine: wines(:barolo))
    assert_not dup.valid?
    assert_includes dup.errors[:wine_id], "has already been taken"
  end

  test "allows the same wine on different lists" do
    item = WineListItem.new(wine_list: wine_lists(:winter), wine: wines(:barolo))
    assert item.valid?
  end

  # --- Same-restaurant constraint ---

  test "rejects a wine from a different restaurant than the list" do
    item = WineListItem.new(wine_list: wine_lists(:summer), wine: wines(:chianti))
    assert_not item.valid?
    assert_includes item.errors[:wine], "must belong to the same restaurant as the list"
  end

  test "does not raise on same-restaurant validation when associations are nil" do
    item = WineListItem.new
    assert_nothing_raised { item.valid? }
  end

  # --- Associations ---

  test "belongs to wine_list and wine" do
    item = wine_list_items(:summer_barolo)
    assert_equal wine_lists(:summer), item.wine_list
    assert_equal wines(:barolo), item.wine
  end
end
