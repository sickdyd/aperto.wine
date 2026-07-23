require "test_helper"

class TableBulkGenerationTest < ActiveSupport::TestCase
  # Use the same restaurant fixture as restaurant_table_test.rb.
  # IMPORTANT: check test/fixtures/restaurant_tables.yml — pick a restaurant
  # whose existing fixture tables don't collide, or clear them in setup with
  # restaurant.restaurant_tables.delete_all for deterministic counts.
  setup do
    @restaurant = restaurants(:osteria)
    @restaurant.restaurant_tables.delete_all
  end

  test "generates floors × tables with localized table-word pattern" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 2, tables_per_floor: 3,
                                  floor_label: "Floor", name_pattern: "table_number")
    assert gen.save
    assert_equal 6, gen.created_count
    assert_equal 0, gen.skipped_count
    areas = @restaurant.restaurant_tables.distinct.pluck(:area).sort
    assert_equal [ "Floor 1", "Floor 2" ], areas
    floor1 = @restaurant.restaurant_tables.where(area: "Floor 1").order(:position)
    assert_equal [ "#{I18n.t('owner.tables.bulk.table_word')} 1",
                   "#{I18n.t('owner.tables.bulk.table_word')} 2",
                   "#{I18n.t('owner.tables.bulk.table_word')} 3" ], floor1.map(&:name)
    assert_equal [ 1, 2, 3 ], floor1.map(&:position)
    assert floor1.all?(&:active?)
    assert floor1.all? { |t| t.token.present? }
  end

  test "single floor with blank label leaves area nil" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 2,
                                  floor_label: "", name_pattern: "number_only")
    assert gen.save
    assert_equal [ nil ], @restaurant.restaurant_tables.distinct.pluck(:area)
    assert_equal [ "1", "2" ], @restaurant.restaurant_tables.order(:position).map(&:name)
  end

  test "single floor with label uses label verbatim as area" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 1,
                                  floor_label: "Terrazza", name_pattern: "t_number")
    assert gen.save
    table = @restaurant.restaurant_tables.sole
    assert_equal "Terrazza", table.area
    assert_equal "T1", table.name
  end

  test "floor_table pattern names tables floor-number" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 2, tables_per_floor: 2,
                                  floor_label: "Piano", name_pattern: "floor_table")
    assert gen.save
    assert_equal [ "1-1", "1-2" ], @restaurant.restaurant_tables.where(area: "Piano 1").order(:position).map(&:name)
    assert_equal [ "2-1", "2-2" ], @restaurant.restaurant_tables.where(area: "Piano 2").order(:position).map(&:name)
  end

  test "skips tables whose name already exists in the same area (case-insensitive)" do
    @restaurant.restaurant_tables.create!(name: "t1", area: "Sala", active: true)
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 2,
                                  floor_label: "Sala", name_pattern: "t_number")
    assert gen.save
    assert_equal 1, gen.created_count
    assert_equal 1, gen.skipped_count
    assert_equal 2, @restaurant.restaurant_tables.count
  end

  test "requires floor_label when more than one floor" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 2, tables_per_floor: 2,
                                  floor_label: "  ", name_pattern: "t_number")
    assert_not gen.save
    assert gen.errors[:floor_label].any?
    assert_equal 0, @restaurant.restaurant_tables.count
  end

  test "rejects out-of-range counts, unknown patterns, and totals over the cap" do
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 0, tables_per_floor: 5, name_pattern: "t_number").save
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 11, tables_per_floor: 5, floor_label: "F", name_pattern: "t_number").save
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 101, name_pattern: "t_number").save
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 5, name_pattern: "evil").save
    over_cap = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 3, tables_per_floor: 100, floor_label: "F", name_pattern: "t_number")
    assert_not over_cap.save
    assert over_cap.errors[:base].any?
  end
end
