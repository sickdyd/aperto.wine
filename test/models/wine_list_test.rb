require "test_helper"

class WineListTest < ActiveSupport::TestCase
  def valid_attributes
    { restaurant: restaurants(:osteria), name: "Featured" }
  end

  # --- Validations ---

  test "creates a valid wine list" do
    assert WineList.new(valid_attributes).valid?
  end

  test "requires name" do
    list = WineList.new(valid_attributes.merge(name: ""))
    assert_not list.valid?
    assert_includes list.errors[:name], "can't be blank"
  end

  test "requires restaurant" do
    list = WineList.new(valid_attributes.merge(restaurant: nil))
    assert_not list.valid?
  end

  test "defaults active to true and position to 0" do
    list = WineList.create!(valid_attributes)
    assert list.active?
    assert_equal 0, list.position
  end

  # --- Associations ---

  test "belongs to restaurant" do
    assert_equal restaurants(:osteria), wine_lists(:summer).restaurant
  end

  test "has many wine_list_items" do
    assert_includes wine_lists(:summer).wine_list_items, wine_list_items(:summer_barolo)
  end

  test "has many wines through items" do
    assert_includes wine_lists(:summer).wines, wines(:barolo)
    assert_includes wine_lists(:summer).wines, wines(:sold_out_wine)
  end

  test "destroys dependent wine_list_items when deleted" do
    list = wine_lists(:summer)
    assert_difference "WineListItem.count", -list.wine_list_items.count do
      list.destroy
    end
  end

  test "destroying a list does not destroy the wines themselves" do
    wine_lists(:summer).destroy
    assert Wine.exists?(wines(:barolo).id)
  end

  # --- Scopes ---

  test "active scope returns only active lists" do
    assert_includes WineList.active, wine_lists(:trattoria_list)
    assert_not_includes WineList.active, wine_lists(:winter)
    assert_not_includes WineList.active, wine_lists(:summer)
  end

  test "by_position orders by position then name" do
    osteria = restaurants(:osteria)
    a = osteria.wine_lists.create!(name: "Zeta", position: 5)
    b = osteria.wine_lists.create!(name: "Alpha", position: 5)
    ordered = osteria.wine_lists.by_position.to_a
    assert ordered.index(b) < ordered.index(a), "same position should tie-break by name"
    assert ordered.index(wine_lists(:summer)) < ordered.index(a)
  end
end
