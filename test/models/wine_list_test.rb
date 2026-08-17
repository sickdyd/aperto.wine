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
    assert list.errors.of_kind?(:name, :blank)
  end

  test "requires restaurant" do
    list = WineList.new(valid_attributes.merge(restaurant: nil))
    assert_not list.valid?
  end

  test "defaults to unpublished with position 0" do
    list = WineList.create!(valid_attributes)
    assert_not list.published?, "publishing is an explicit act, never a side effect of creation"
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

  test "published scope returns only published lists" do
    assert_includes WineList.published, wine_lists(:trattoria_list)
    assert_not_includes WineList.published, wine_lists(:winter)
    assert_not_includes WineList.published, wine_lists(:summer)
  end

  # --- Publishing ---

  test "publish! retires the restaurant's previously published list" do
    incumbent = wine_lists(:osteria_list)
    challenger = wine_lists(:summer)

    challenger.publish!

    assert challenger.reload.published?
    assert_not incumbent.reload.published?
  end

  test "publish! leaves another restaurant's published list alone" do
    other = wine_lists(:trattoria_list)

    wine_lists(:summer).publish!

    assert other.reload.published?
  end

  test "publish! on the already published list is a no-op" do
    list = wine_lists(:osteria_list)

    list.publish!

    assert list.reload.published?
    assert_equal 1, restaurants(:osteria).wine_lists.published.count
  end

  test "a restaurant can never have two published lists" do
    assert_raises ActiveRecord::RecordNotUnique do
      wine_lists(:summer).update_column(:published, true)
    end
  end

  test "published_wine_list returns the restaurant's one public list" do
    assert_equal wine_lists(:osteria_list), restaurants(:osteria).published_wine_list
  end

  test "published_wine_list is nil when nothing is published" do
    restaurants(:osteria).wine_lists.update_all(published: false)

    assert_nil restaurants(:osteria).reload.published_wine_list
  end

  test "in_display_order orders by name" do
    osteria = restaurants(:osteria)
    a = osteria.wine_lists.create!(name: "Zeta")
    b = osteria.wine_lists.create!(name: "Alpha")
    ordered = osteria.wine_lists.in_display_order.to_a
    assert ordered.index(b) < ordered.index(a), "lists should be ordered by name"
    assert ordered.index(wine_lists(:summer)) < ordered.index(a)
  end

  # The `position` column is no longer written by any form and is dropped in a
  # later deploy; until then a stale value must not perturb the display order.
  test "in_display_order ignores a stale position value" do
    osteria = restaurants(:osteria)
    zeta  = osteria.wine_lists.create!(name: "Zeta", position: 1)
    alpha = osteria.wine_lists.create!(name: "Alpha", position: 99)
    ordered = osteria.wine_lists.in_display_order.to_a

    assert_operator ordered.index(alpha), :<, ordered.index(zeta)
  end
end
