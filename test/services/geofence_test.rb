require "test_helper"

class GeofenceTest < ActiveSupport::TestCase
  setup do
    # osteria is the only fixture with coordinates (45.4642, 9.1900) and a 200m
    # radius. The geofence ships off, so every fixture has it disabled and the
    # tests that want it on say so.
    @osteria = restaurants(:osteria)
    @osteria.update!(geofence_enabled: true)

    # No coordinates at all — the fails-open case.
    @trattoria = restaurants(:trattoria)
  end

  # A point due north of the restaurant, `meters` away. Derived from a real
  # distance measurement rather than a hardcoded latitude: the boundary tests
  # below are only meaningful if they track MAX_ACCURACY_METERS and the
  # fixture's radius, and a magic literal would quietly stop doing that the
  # first time either moves.
  def point_at(restaurant, meters)
    origin = [ restaurant.latitude.to_f, restaurant.longitude.to_f ]
    probe = 0.001
    meters_per_degree = meters_between(origin, [ origin.first + probe, origin.last ]) / probe
    [ origin.first + (meters / meters_per_degree), origin.last ]
  end

  def meters_between(from, to)
    Geocoder::Calculations.distance_between(from, to, units: :km) * 1000
  end

  def call_at(restaurant, point, accuracy:)
    Geofence.call(restaurant: restaurant, latitude: point.first, longitude: point.last, accuracy: accuracy)
  end

  # --- step 1 and 2: no claim is made at all ---

  test "a disabled geofence makes no claim even when a perfect fix is supplied" do
    @osteria.update!(geofence_enabled: false)

    result = call_at(@osteria, point_at(@osteria, 5), accuracy: 10)

    assert_equal :not_checked, result.status
    assert result.allowed?
    assert_nil result.distance_meters
    assert_nil result.accuracy_meters
  end

  test "an enabled geofence with no restaurant coordinates fails open" do
    # Restaurant validates against this combination, so it can only be reached
    # by data that predates the validation or bypasses it — assigned, never
    # saved, because the model would refuse the save.
    @trattoria.geofence_enabled = true

    result = call_at(@trattoria, [ 45.4642, 9.1900 ], accuracy: 10)

    assert_equal :not_checked, result.status
    assert result.allowed?
  end

  test "an enabled geofence with only a latitude on the restaurant fails open" do
    @trattoria.geofence_enabled = true
    @trattoria.latitude = 45.4642

    result = call_at(@trattoria, [ 45.4642, 9.1900 ], accuracy: 10)

    assert_equal :not_checked, result.status
  end

  # --- step 3: the supplied fix is unusable ---

  test "no fix at all is unverified" do
    result = Geofence.call(restaurant: @osteria)

    assert_equal :unverified, result.status
    assert result.allowed?
    assert_nil result.distance_meters
    assert_nil result.accuracy_meters
  end

  test "a latitude without a longitude is unverified" do
    result = Geofence.call(restaurant: @osteria, latitude: 45.4642, longitude: nil, accuracy: 10)

    assert_equal :unverified, result.status
  end

  test "a longitude without a latitude is unverified" do
    result = Geofence.call(restaurant: @osteria, latitude: nil, longitude: 9.1900, accuracy: 10)

    assert_equal :unverified, result.status
  end

  test "non-numeric junk in any parameter is unverified and never raises" do
    junk = [ "abc", [], {}, true, Object.new ]

    junk.each do |value|
      assert_equal :unverified,
        Geofence.call(restaurant: @osteria, latitude: value, longitude: 9.1900, accuracy: 10).status,
        "latitude #{value.inspect}"
      assert_equal :unverified,
        Geofence.call(restaurant: @osteria, latitude: 45.4642, longitude: value, accuracy: 10).status,
        "longitude #{value.inspect}"
      assert_equal :unverified,
        Geofence.call(restaurant: @osteria, latitude: 45.4642, longitude: 9.1900, accuracy: value).status,
        "accuracy #{value.inspect}"
    end
  end

  test "NaN and Infinity in any parameter are unverified and never raise" do
    [ Float::NAN, Float::INFINITY, -Float::INFINITY ].each do |value|
      assert_equal :unverified,
        Geofence.call(restaurant: @osteria, latitude: value, longitude: 9.1900, accuracy: 10).status,
        "latitude #{value.inspect}"
      assert_equal :unverified,
        Geofence.call(restaurant: @osteria, latitude: 45.4642, longitude: value, accuracy: 10).status,
        "longitude #{value.inspect}"
      assert_equal :unverified,
        Geofence.call(restaurant: @osteria, latitude: 45.4642, longitude: 9.1900, accuracy: value).status,
        "accuracy #{value.inspect}"
    end
  end

  test "a latitude outside -90..90 is unverified" do
    [ 91, -91, 180, -180 ].each do |latitude|
      result = Geofence.call(restaurant: @osteria, latitude: latitude, longitude: 9.1900, accuracy: 10)

      assert_equal :unverified, result.status, "latitude #{latitude}"
    end
  end

  test "a longitude outside -180..180 is unverified" do
    [ 181, -181, 360 ].each do |longitude|
      result = Geofence.call(restaurant: @osteria, latitude: 45.4642, longitude: longitude, accuracy: 10)

      assert_equal :unverified, result.status, "longitude #{longitude}"
    end
  end

  test "the extremes of the valid ranges are still judged" do
    result = Geofence.call(restaurant: @osteria, latitude: 90, longitude: 180, accuracy: 10)

    assert_equal :out_of_range, result.status
  end

  # --- step 4: the fix is too imprecise to support any verdict ---

  test "a missing accuracy is unverified" do
    result = call_at(@osteria, point_at(@osteria, 5), accuracy: nil)

    assert_equal :unverified, result.status
    assert_nil result.accuracy_meters
  end

  test "a negative accuracy is unverified" do
    result = call_at(@osteria, point_at(@osteria, 5), accuracy: -1)

    assert_equal :unverified, result.status
    assert_nil result.accuracy_meters
  end

  test "an accuracy above the cap is unverified" do
    result = call_at(@osteria, point_at(@osteria, 5), accuracy: Geofence::MAX_ACCURACY_METERS + 1)

    assert_equal :unverified, result.status
  end

  test "an accuracy exactly at the cap is still judged" do
    result = call_at(@osteria, point_at(@osteria, 5), accuracy: Geofence::MAX_ACCURACY_METERS)

    assert_equal :verified, result.status
    assert_equal Geofence::MAX_ACCURACY_METERS, result.accuracy_meters
  end

  test "a too-imprecise fix reports the accuracy but no distance" do
    result = call_at(@osteria, point_at(@osteria, 5), accuracy: 800)

    assert_equal :unverified, result.status
    assert_equal 800, result.accuracy_meters
    assert_nil result.distance_meters
  end

  # --- step 5: the actual proximity decision ---

  test "a fix a few metres away is verified" do
    result = call_at(@osteria, point_at(@osteria, 5), accuracy: 12)

    assert_equal :verified, result.status
    assert result.allowed?
    assert_equal 5, result.distance_meters
    assert_equal 12, result.accuracy_meters
  end

  test "a fix several kilometres away is out of range and reports the distance" do
    result = call_at(@osteria, point_at(@osteria, 4000), accuracy: 12)

    assert_equal :out_of_range, result.status
    assert_not result.allowed?
    assert_equal 4000, result.distance_meters
    assert_equal 12, result.accuracy_meters
  end

  test "a distance exactly equal to the radius plus the accuracy is verified" do
    accuracy = 30
    budget = @osteria.proximity_radius_meters + accuracy

    result = call_at(@osteria, point_at(@osteria, budget), accuracy: accuracy)

    assert_equal :verified, result.status
    assert_equal budget, result.distance_meters
  end

  test "one metre beyond the radius plus the accuracy is out of range" do
    accuracy = 30
    budget = @osteria.proximity_radius_meters + accuracy

    result = call_at(@osteria, point_at(@osteria, budget + 1), accuracy: accuracy)

    assert_equal :out_of_range, result.status
    assert_equal budget + 1, result.distance_meters
  end

  test "the accuracy allowance is what admits a fix past the bare radius" do
    # The same position is out of range with a tight fix and verified with a
    # loose one: proof the allowance in step 5 is doing the work, not slack in
    # the radius.
    point = point_at(@osteria, @osteria.proximity_radius_meters + 40)

    assert_equal :out_of_range, call_at(@osteria, point, accuracy: 10).status
    assert_equal :verified, call_at(@osteria, point, accuracy: 60).status
  end

  # --- the result contract ---

  test "only an out-of-range placement is disallowed" do
    assert Geofence::Result.new(status: :not_checked).allowed?
    assert Geofence::Result.new(status: :verified).allowed?
    assert Geofence::Result.new(status: :unverified).allowed?
    assert_not Geofence::Result.new(status: :out_of_range).allowed?
  end

  test "every persistable status is a member of Order's location_status enum" do
    # The two enums are meant to line up exactly, minus :out_of_range, which is
    # never persisted because that placement is rejected.
    persistable = [ :not_checked, :verified, :unverified ]

    assert_equal persistable.map(&:to_s).sort, Order.location_statuses.keys.sort
  end

  test "coordinates arriving as strings are judged, not discarded" do
    # The fix reaches this service from a JSON request body, so numeric strings
    # are the normal shape rather than an edge case.
    point = point_at(@osteria, 5)
    result = Geofence.call(
      restaurant: @osteria,
      latitude: point.first.to_s,
      longitude: point.last.to_s,
      accuracy: "12.4"
    )

    assert_equal :verified, result.status
    assert_equal 12, result.accuracy_meters
  end
end
