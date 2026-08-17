# Decides whether an order may be placed from where the diner's device says it
# is. Follows the precedent set by PlaceOrder and QrSvgRenderer: a plain service
# object with a single .call class method. It performs no I/O and writes
# nothing — it reads the restaurant it is handed and returns a verdict.
#
# Two facts shape every rule below.
#
# The coordinates are attacker-controlled. They arrive from a public,
# unauthenticated endpoint fed by the browser Geolocation API, so nothing about
# them is assumed: not that they are numbers, not that they are finite, not
# that they name a point on Earth. Anything that fails those checks is treated
# as "no usable fix" rather than as an error.
#
# Indoor GPS is bad. A phone inside a stone-walled restaurant routinely reports
# a fix it can only place to within ±50-100m. A naive `distance <= radius` check
# turns honest diners away, which is the largest product risk in this feature —
# hence the accuracy allowance in step 5 and the cap in step 4 that makes it
# safe.
class Geofence
  # The widest confidence circle a fix may carry and still be judged. Beyond
  # this the device is telling us it cannot place itself within a margin
  # comparable to a small restaurant's whole neighbourhood, and neither verdict
  # would be honest.
  MAX_ACCURACY_METERS = 150

  # `status` is one of:
  #
  #   :not_checked  - no claim was made: the geofence is off, or the restaurant
  #                   has no coordinates to measure from.
  #   :verified     - a usable fix was supplied and it was within range.
  #   :unverified   - no usable fix was supplied, or it was too imprecise to
  #                   judge either way. The order is still allowed.
  #   :out_of_range - a usable fix was supplied and it was outside the radius.
  #                   The only status that blocks the placement.
  #
  # The first three map exactly onto Order's location_status enum. That enum has
  # only three members on purpose: an :out_of_range placement is rejected, so no
  # order row ever exists to carry it.
  Result = Struct.new(:status, :distance_meters, :accuracy_meters, keyword_init: true) do
    def allowed?
      status != :out_of_range
    end
  end

  def self.call(restaurant:, latitude: nil, longitude: nil, accuracy: nil)
    new(restaurant: restaurant, latitude: latitude, longitude: longitude, accuracy: accuracy).call
  end

  def initialize(restaurant:, latitude:, longitude:, accuracy:)
    @restaurant = restaurant
    @latitude = latitude
    @longitude = longitude
    @accuracy = accuracy
  end

  # The order of these checks is the policy, and it runs from "no claim" through
  # "cannot judge" to the actual proximity decision.
  def call
    return not_checked unless restaurant.geofence_enabled?

    # Restaurant validates against enabling a geofence without coordinates, so
    # reaching this line means the restaurant's own data is broken. It fails
    # OPEN: a data problem on the restaurant's side must never silently stop a
    # paying diner from ordering.
    return not_checked if origin.nil?

    return unverified unless fix_usable?

    # A fix the device itself cannot place within MAX_ACCURACY_METERS supports
    # neither verdict: it is equally consistent with a diner at the bar and one
    # across the piazza. The accuracy is still reported, because "the fix was
    # ±800m" is exactly what an owner needs to interpret the flag later.
    return unverified(accuracy_meters: reportable_accuracy) unless accuracy_usable?

    judge
  end

  private

  attr_reader :restaurant, :latitude, :longitude, :accuracy

  def judge
    distance = rounded_distance

    # The deliberate lenient reading: accept when the device's own confidence
    # circle overlaps the geofence, rather than demanding the reported centre
    # sit inside it. This is only safe because step 4 caps how large that circle
    # may get — remove MAX_ACCURACY_METERS and any device can claim an accuracy
    # wide enough to cover the city, which quietly turns the feature off.
    #
    # Both sides are the rounded integers rather than the raw floats, so an
    # owner reading distance_meters and location_accuracy_meters off the order
    # row can reconstruct exactly the decision that was made here.
    status = distance <= restaurant.proximity_radius_meters + rounded_accuracy ? :verified : :out_of_range

    Result.new(status: status, distance_meters: distance, accuracy_meters: rounded_accuracy)
  end

  def not_checked
    Result.new(status: :not_checked, distance_meters: nil, accuracy_meters: nil)
  end

  # distance_meters stays nil here on purpose. A distance derived from a fix we
  # have just rejected as unusable would put a number in front of an owner that
  # means nothing.
  def unverified(accuracy_meters: nil)
    Result.new(status: :unverified, distance_meters: nil, accuracy_meters: accuracy_meters)
  end

  def origin
    return nil if restaurant.latitude.nil? || restaurant.longitude.nil?

    [ restaurant.latitude.to_f, restaurant.longitude.to_f ]
  end

  def fix_usable?
    fix_latitude&.between?(-90, 90) && fix_longitude&.between?(-180, 180)
  end

  def accuracy_usable?
    fix_accuracy&.between?(0, MAX_ACCURACY_METERS)
  end

  def fix_latitude
    @fix_latitude ||= finite_float(latitude)
  end

  def fix_longitude
    @fix_longitude ||= finite_float(longitude)
  end

  def fix_accuracy
    @fix_accuracy ||= finite_float(accuracy)
  end

  # nil for anything that is not a real number, including NaN and Infinity,
  # which are numbers to Ruby but would sail through a range check
  # (NaN#between? is false, but Infinity's is not) and poison the arithmetic.
  # Strings are coerced rather than rejected: the fix arrives from a JSON
  # request body, so numeric strings are the normal shape here.
  def finite_float(value)
    float = Float(value, exception: false)
    float if float&.finite?
  end

  # The rounded accuracy is used for both reporting and the comparison in
  # #judge, so an order row is always self-consistent. Reached only after
  # #accuracy_usable?, so it is never nil there.
  def rounded_accuracy
    fix_accuracy&.round
  end

  # What is worth recording when the accuracy was rejected. A number too large
  # to judge is still meaningful to an owner reviewing the order ("the fix was
  # ±800m" explains the flag). A missing or negative one is not: a negative
  # radius describes nothing, so recording it would only invite the reader to
  # interpret a value that has no meaning.
  def reportable_accuracy
    rounded_accuracy if fix_accuracy && !fix_accuracy.negative?
  end

  def rounded_distance
    # units: :km is passed explicitly. Geocoder has a global units setting that
    # another part of the app — or a future initializer — is free to change, and
    # an implicit unit here would silently start comparing miles against a
    # radius measured in metres.
    (Geocoder::Calculations.distance_between(origin, [ fix_latitude, fix_longitude ], units: :km) * 1000).round
  end
end
