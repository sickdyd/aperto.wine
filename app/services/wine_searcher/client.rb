module WineSearcher
  Result = Struct.new(:name, :producer, :region, :grape_variety, :vintage_year, :color, keyword_init: true)

  # Sole owner of Wine-Searcher HTTP concerns. Request params and the parsed
  # response shape follow the documented Wine Check API; the exact schema is
  # only visible with an API key, so all payload knowledge is confined to
  # parse_results/build_result (see spec "Rollout" step 2).
  class Client
    MIN_QUERY_LENGTH = 3
    OPEN_TIMEOUT_SECONDS = 2
    READ_TIMEOUT_SECONDS = 3
    VINTAGE_RANGE = (1900..).freeze
    CACHE_TTL = 24.hours
    CACHE_NAMESPACE = "wine_searcher/v1".freeze

    # Sentinel: rescue paths return this exact frozen array so search can tell
    # "upstream failed" (don't cache) from "no matches" (cache it).
    FAILURE = [].freeze

    # Ordered: more specific substrings before generic ones.
    COLOR_BY_STYLE = {
      "sparkling" => "sparkling", "champagne" => "sparkling",
      "dessert" => "dessert", "sweet" => "dessert", "fortified" => "dessert", "port" => "dessert",
      "rose" => "rose", "rosé" => "rose",
      "white" => "white", "red" => "red"
    }.freeze

    def configured?
      api_key.present? && api_url.present?
    end

    def search(query)
      normalized = query.to_s.strip
      return [] if normalized.length < MIN_QUERY_LENGTH || !configured?

      cache_key = "#{CACHE_NAMESPACE}/#{normalized.downcase}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      fetch_results(normalized).tap do |results|
        # A failed upstream call returns [] via the rescue in fetch_results and
        # must stay uncached so the next keystroke can retry; a genuine empty
        # result set IS cached (negative caching) to protect the daily quota.
        Rails.cache.write(cache_key, results, expires_in: CACHE_TTL) unless results.equal?(FAILURE)
      end
    end

    private

    def api_key
      Rails.application.credentials.dig(:wine_searcher, :api_key).presence || ENV["WINE_SEARCHER_API_KEY"].presence
    end

    def api_url
      Rails.application.credentials.dig(:wine_searcher, :api_url).presence || ENV["WINE_SEARCHER_API_URL"].presence
    end

    def fetch_results(query)
      uri = URI.parse(api_url)
      uri.query = URI.encode_www_form(api_key: api_key, winename: query, output: "json")

      response = perform_request(uri)
      unless response.is_a?(Net::HTTPOK)
        Rails.logger.warn("[wine_searcher] non-200 response: #{response.code}")
        return FAILURE
      end

      parse_results(JSON.parse(response.body))
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
           IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      Rails.logger.warn("[wine_searcher] search failed: #{e.class}: #{e.message}")
      FAILURE
    end

    def perform_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT_SECONDS
      http.read_timeout = READ_TIMEOUT_SECONDS
      http.get(uri.request_uri, "User-Agent" => "aperto.wine")
    end

    def parse_results(payload)
      wines = payload["wines"] || payload["wine"]
      Array.wrap(wines).filter_map { |entry| build_result(entry) }
    end

    def build_result(entry)
      return nil unless entry.is_a?(Hash)

      name = entry["wine-name"].presence
      return nil unless name

      Result.new(
        name: name,
        producer: entry["producer"].presence,
        region: entry["region"].presence,
        grape_variety: entry["grape"].presence,
        vintage_year: parse_vintage(entry["vintage"]),
        color: derive_color(entry["wine-type"] || entry["style"])
      )
    end

    def parse_vintage(value)
      year = Integer(value.to_s, exception: false)
      year if year && VINTAGE_RANGE.cover?(year) && year <= Date.current.year
    end

    def derive_color(style)
      normalized = style.to_s.downcase
      return nil if normalized.blank?

      COLOR_BY_STYLE.find { |fragment, _| normalized.include?(fragment) }&.last
    end
  end
end
