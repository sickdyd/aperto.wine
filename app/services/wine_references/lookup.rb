module WineReferences
  # Type-ahead search over the local wine reference catalogue. Replaces the
  # former Wine-Searcher HTTP client: same result shape, no network, no quota.
  #
  # The query is deliberately shaped as three separately-bounded rank tiers
  # UNION ALL'd together rather than one scan with a CASE expression in the
  # ORDER BY. A ranking expression is not sargable, so Postgres had to fetch
  # EVERY match before it could sort and apply the LIMIT — cost that grows with
  # the size of the match set, on an endpoint that fires on every keystroke
  # (measured on 100k rows: ~31 ms for a substring matching 35k rows). Giving
  # each tier its own LIMIT lets the planner stop as soon as that tier is full,
  # so the work is bounded by 3 x LIMIT rows regardless of table size (~0.6 ms
  # for the same query).
  class Lookup
    MIN_QUERY_LENGTH = 3
    LIMIT = 8

    # Keys must stay exactly these: the wine-autofill Stimulus controller reads
    # them straight off the JSON payload.
    Result = Struct.new(:name, :producer, :region, :grape_variety, :vintage_year, :color,
                        keyword_init: true)

    COLUMNS = "id, name, producer, region, grape_variety, vintages, color".freeze

    # Rank 0 exact name, 1 name prefix, 2 name-or-producer substring — the same
    # order the CASE expression used to produce. The tiers deliberately overlap
    # (each predicate is a superset of the one above) instead of excluding each
    # other: a NOT ILIKE exclusion is opaque to the planner and pushed it onto a
    # full sequential scan. Overlap costs nothing here because the broadest tier
    # alone always yields LIMIT rows when that many matches exist, and DISTINCT
    # ON collapses a row that surfaced in several tiers onto its best rank.
    TIERS = [
      [ 0, "name ILIKE :exact" ],
      [ 1, "name ILIKE :prefix" ],
      [ 2, "name ILIKE :contains OR producer ILIKE :contains" ]
    ].freeze

    TIER_SQL = TIERS.map do |rank, condition|
      "(SELECT #{COLUMNS}, #{rank} AS match_rank FROM wine_references WHERE #{condition} LIMIT :limit)"
    end.join(" UNION ALL ").freeze

    # The outer query only ever ranks the <= 3 x LIMIT rows the tiers returned.
    SQL = <<~SQL.freeze
      SELECT #{COLUMNS} FROM (
        SELECT DISTINCT ON (id) #{COLUMNS}, match_rank
        FROM (#{TIER_SQL}) AS tiers
        ORDER BY id, match_rank
      ) AS ranked
      ORDER BY match_rank, name, id
      LIMIT :limit
    SQL

    def search(query)
      normalized = query.to_s.strip
      return [] if normalized.length < MIN_QUERY_LENGTH

      # sanitize_sql_like neutralises %, _ and \ so a query is always matched
      # literally; the patterns themselves are bound, never interpolated.
      escaped = ActiveRecord::Base.sanitize_sql_like(normalized)

      matches(escaped).map { |reference| build_result(reference) }
    end

    private

    def matches(escaped)
      WineReference.find_by_sql([ SQL, patterns(escaped) ])
    end

    def patterns(escaped)
      { exact: escaped, prefix: "#{escaped}%", contains: "%#{escaped}%", limit: LIMIT }
    end

    def build_result(reference)
      Result.new(
        name: reference.name,
        producer: reference.producer,
        region: reference.region,
        grape_variety: reference.grape_variety,
        vintage_year: reference.latest_vintage,
        color: reference.color
      )
    end
  end
end
