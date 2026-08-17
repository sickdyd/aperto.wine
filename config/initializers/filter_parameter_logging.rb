# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # A diner's position fix, sent to OrdersController#create by the geofence.
  # Filtering it is not belt-and-braces: the whole point of storing only a
  # derived distance on the order (see the AddGeofencing migration) is that the
  # app never holds a place a diner has stood. Rails logs request parameters at
  # info, and production runs at info, so without these three every geofenced
  # order would write the precise coordinates straight to the log stream and
  # undo that decision in the one place nobody thinks to look.
  :latitude, :longitude, :accuracy
]
