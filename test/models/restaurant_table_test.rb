require "test_helper"

class RestaurantTableTest < ActiveSupport::TestCase
  setup do
    @restaurant = restaurants(:osteria)
  end

  test "valid with name and restaurant" do
    table = @restaurant.restaurant_tables.build(name: "Tavolo 10")
    assert table.valid?
  end

  test "invalid without name" do
    table = @restaurant.restaurant_tables.build(name: "")
    assert_not table.valid?
    assert table.errors.of_kind?(:name, :blank)
  end

  test "name must be unique within restaurant and area" do
    duplicate = @restaurant.restaurant_tables.build(name: "Tavolo 1", area: "Sala principale")
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "database rejects a duplicate name even when validations are bypassed" do
    duplicate = @restaurant.restaurant_tables.build(name: "tavolo 1", area: "Sala principale")
    assert_raises ActiveRecord::RecordNotUnique do
      duplicate.save!(validate: false)
    end
  end

  test "same name allowed in a different area" do
    table = @restaurant.restaurant_tables.build(name: "Tavolo 2", area: "Dehors")
    assert table.valid?
  end

  test "same name allowed in another restaurant" do
    table = restaurants(:trattoria).restaurant_tables.build(name: "Tavolo 2", area: "Sala principale")
    assert table.valid?
  end

  test "generates a token on create" do
    table = @restaurant.restaurant_tables.create!(name: "Tavolo 11")
    assert table.token.present?
    assert_operator table.token.length, :>=, 24
  end

  test "tokens are unique" do
    a = @restaurant.restaurant_tables.create!(name: "Tavolo 12")
    b = @restaurant.restaurant_tables.create!(name: "Tavolo 13")
    assert_not_equal a.token, b.token
  end

  test "active scope excludes inactive tables" do
    assert_includes RestaurantTable.active, restaurant_tables(:sala_t1)
    assert_not_includes RestaurantTable.active, restaurant_tables(:retired_table)
  end

  test "in_display_order orders by area then name" do
    tables = @restaurant.restaurant_tables.in_display_order.to_a
    areas = tables.map(&:area)
    assert_equal areas.sort_by(&:to_s), areas

    sala = tables.select { |table| table.area == "Sala principale" }.map(&:name)
    assert_equal sala.sort, sala
  end

  # The `position` column is no longer written by any form and is dropped in a
  # later deploy; until then a stale value must not perturb the display order.
  test "in_display_order ignores a stale position value" do
    zeta  = @restaurant.restaurant_tables.create!(name: "Zeta", area: "Veranda", position: 1)
    alpha = @restaurant.restaurant_tables.create!(name: "Alpha", area: "Veranda", position: 99)

    ordered = @restaurant.restaurant_tables.in_display_order.to_a

    assert_operator ordered.index(alpha), :<, ordered.index(zeta)
  end

  test "grouped_by_area groups ordered tables" do
    groups = @restaurant.restaurant_tables.grouped_by_area
    assert_includes groups.keys, "Sala principale"
    assert_includes groups.keys, "Dehors"
    assert_equal [ "Tavolo 1", "Tavolo 2", "Tavolo dismesso" ], groups["Sala principale"].map(&:name)
  end

  test "destroying a table nullifies its orders instead of deleting them" do
    table = restaurant_tables(:sala_t1)
    order = orders(:pending_order)
    order.update!(restaurant_table: table)

    assert_no_difference "Order.count" do
      table.destroy!
    end
    assert_nil order.reload.restaurant_table_id
  end

  test "destroying a restaurant destroys its tables" do
    restaurant = restaurants(:trattoria)
    assert_difference "RestaurantTable.count", -restaurant.restaurant_tables.count do
      restaurant.destroy!
    end
  end

  test "blank area is normalized to nil" do
    table = RestaurantTable.new(area: "  ")
    assert_nil table.area
  end
end
