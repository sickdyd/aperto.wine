require "test_helper"

# Guards the log-filtering side of the geofence's privacy decision. The order
# row deliberately stores only a derived distance and never the diner's
# coordinates (see the AddGeofencing migration), and that is only true end to
# end if the coordinates also stay out of the request log — Rails logs
# parameters at info and production runs at info.
#
# Asserted through a real ParameterFilter rather than by checking list
# membership, so the test covers the behaviour (including the partial matching
# that makes `restaurant[latitude]` filter too) instead of the spelling.
class ParameterFilteringTest < ActiveSupport::TestCase
  setup do
    @filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  end

  test "a diner's position fix never reaches the log" do
    filtered = @filter.filter("latitude" => "45.4642", "longitude" => "9.1900", "accuracy" => "12.5")

    assert_equal "[FILTERED]", filtered["latitude"]
    assert_equal "[FILTERED]", filtered["longitude"]
    assert_equal "[FILTERED]", filtered["accuracy"]
  end

  test "the restaurant's own coordinates are filtered too" do
    filtered = @filter.filter("restaurant" => { "latitude" => "45.4642", "longitude" => "9.1900" })

    assert_equal "[FILTERED]", filtered["restaurant"]["latitude"]
    assert_equal "[FILTERED]", filtered["restaurant"]["longitude"]
  end

  test "ordinary order params still reach the log" do
    filtered = @filter.filter("guest_name" => "Jane", "quantity" => "2")

    assert_equal "Jane", filtered["guest_name"]
    assert_equal "2", filtered["quantity"]
  end
end
