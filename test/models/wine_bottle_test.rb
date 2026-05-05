require "test_helper"

class WineBottleTest < ActiveSupport::TestCase
  def valid_attributes
    {
      wine: wines(:barolo),
      status: :sealed,
      glasses_remaining: 10
    }
  end

  # --- Validations / basic creation ---

  test "creates a valid wine bottle" do
    bottle = WineBottle.new(valid_attributes)
    assert bottle.valid?
  end

  test "requires wine" do
    bottle = WineBottle.new(valid_attributes.merge(wine: nil))
    assert_not bottle.valid?
  end

  # --- Enums ---

  test "status enum values" do
    assert_equal 0, WineBottle.statuses[:sealed]
    assert_equal 1, WineBottle.statuses[:open]
    assert_equal 2, WineBottle.statuses[:empty]
  end

  test "status predicate methods work" do
    bottle = wine_bottles(:sealed_barolo)
    assert bottle.sealed?
    assert_not bottle.open?
    assert_not bottle.empty?
  end

  test "open bottle predicate is true for open bottle" do
    bottle = wine_bottles(:open_gavi)
    assert bottle.open?
    assert_not bottle.sealed?
  end

  # --- Scopes ---

  test "current scope includes sealed bottles" do
    assert_includes WineBottle.current, wine_bottles(:sealed_barolo)
  end

  test "current scope includes open bottles" do
    assert_includes WineBottle.current, wine_bottles(:open_gavi)
  end

  test "current scope excludes empty bottles" do
    bottle = WineBottle.create!(valid_attributes.merge(status: :empty))
    assert_not_includes WineBottle.current, bottle
  end

  # --- open! method ---

  test "open! changes status from sealed to open" do
    bottle = WineBottle.create!(valid_attributes.merge(status: :sealed))
    bottle.open!
    assert bottle.reload.open?
  end

  test "open! sets opened_at timestamp" do
    bottle = WineBottle.create!(valid_attributes.merge(status: :sealed, opened_at: nil))
    freeze_time do
      bottle.open!
      assert_equal Time.current, bottle.reload.opened_at
    end
  end

  test "open! persists changes to the database" do
    bottle = WineBottle.create!(valid_attributes.merge(status: :sealed))
    bottle.open!
    reloaded = WineBottle.find(bottle.id)
    assert reloaded.open?
    assert_not_nil reloaded.opened_at
  end

  # --- Associations ---

  test "belongs to wine" do
    assert_equal wines(:barolo), wine_bottles(:sealed_barolo).wine
  end
end
