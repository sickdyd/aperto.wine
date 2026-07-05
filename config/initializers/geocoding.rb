# Country scope for address suggestions and fallback geocoding, as ISO
# 3166-1 alpha-2 codes. Add codes to expand to new markets; an empty
# array means worldwide.
Rails.application.config.x.geocoding.country_codes = [ "IT" ]

# Photon (photon.komoot.io): free, keyless geocoding on OpenStreetMap data,
# built for search-as-you-type. The public instance is best-effort — every
# caller must degrade gracefully when it is unavailable.
Geocoder.configure(
  lookup: :photon,
  use_https: true,
  timeout: 2,
  units: :km
)
