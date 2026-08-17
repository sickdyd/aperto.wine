class AddGeofencing < ActiveRecord::Migration[8.1]
  def change
    # Ships dark: no existing restaurant changes behaviour until an owner turns
    # it on, and turning it on is refused without coordinates to measure from.
    add_column :restaurants, :geofence_enabled, :boolean, null: false, default: false

    # What the app learned about where the order was placed from. Deliberately
    # NOT the diner's latitude/longitude: a precise position is personal data
    # under the GDPR, and storing it would turn every order row into a point in
    # a location history the product has no use for. The derived distance plus
    # the accuracy of the fix are enough for an owner to review a disputed
    # order, and neither can be walked back into a place the diner has been.
    add_column :orders, :location_status, :integer, null: false, default: 0
    add_column :orders, :distance_meters, :integer
    add_column :orders, :location_accuracy_meters, :integer
  end
end
