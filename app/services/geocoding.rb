# Address geocoding via Photon (OpenStreetMap data). Used by the owner
# address autocomplete endpoint and Restaurant's fallback geocoding.
# Results are ODbL-licensed: any UI showing them must attribute
# "© OpenStreetMap contributors".
module Geocoding
  SUGGESTION_LIMIT = 5
  MIN_QUERY_LENGTH = 3
  MAX_QUERY_LENGTH = 200
  CACHE_TTL = 1.day
  # Geographic center of Italy — ranks nearby results first without
  # excluding other countries (filtering is allowed_country?'s job).
  BIAS_LATITUDE = 42.5
  BIAS_LONGITUDE = 12.5

  class << self
    def country_codes
      Rails.application.config.x.geocoding.country_codes
    end

    def allowed_country?(code)
      country_codes.empty? || country_codes.include?(code.to_s.upcase)
    end

    def suggestions(query)
      query = query.to_s.strip
      return [] if query.length < MIN_QUERY_LENGTH

      query = query[0, MAX_QUERY_LENGTH]

      # skip_nil: fetch_suggestions returns nil when the lookup fails, and
      # failures must not be cached — otherwise one transient Photon outage
      # would blank out this query's suggestions for the whole TTL. A
      # legitimate empty result set ([]) is still cached.
      cache_key = [ "address_suggestions", I18n.locale, query.downcase ]
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, skip_nil: true) do
        fetch_suggestions(query)
      end || []
    end

    private

    def fetch_suggestions(query)
      results = Geocoder.search(query, params: {
        limit: SUGGESTION_LIMIT,
        lat: BIAS_LATITUDE,
        lon: BIAS_LONGITUDE,
        lang: photon_lang
      })
      results.filter_map { |result| suggestion_from(result) }
    rescue StandardError => e
      Rails.logger.warn("Geocoding.suggestions failed: #{e.class}: #{e.message}")
      nil
    end

    def suggestion_from(result)
      properties = result.data["properties"] || {}
      return nil unless allowed_country?(properties["countrycode"])

      longitude, latitude = result.data.dig("geometry", "coordinates")
      return nil if latitude.nil? || longitude.nil?

      { label: format_label(properties), latitude: latitude, longitude: longitude }
    end

    # "Name, Street 42, 20121 Milano, Italia" — blank parts skipped,
    # consecutive duplicates collapsed.
    def format_label(properties)
      street = [ properties["street"], properties["housenumber"] ].compact.join(" ")
      city = [ properties["postcode"], properties["city"] ].compact.join(" ")
      [ properties["name"], street, city, properties["country"] ]
        .filter_map { |part| part.to_s.strip.presence }
        .uniq
        .join(", ")
    end

    # Photon supports en/de/fr/it; fall back to English for other locales.
    def photon_lang
      %w[en it].include?(I18n.locale.to_s) ? I18n.locale.to_s : "en"
    end
  end
end
