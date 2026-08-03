require "csv"

module WineReferences
  # Imports an X-Wines CSV (CC0-1.0) into wine_references. Idempotent: rows are
  # upserted on external_id, so re-running refreshes changed fields instead of
  # duplicating.
  #
  # A single unusable ROW never aborts the run — it is counted as skipped and
  # the import carries on. A STRUCTURAL error (an unterminated quote, say)
  # cannot be recovered from: CSV parsing stops there and every remaining line
  # is lost. That case is reported through Summary#truncated? rather than
  # swallowed, because otherwise the counts look plausible but describe only a
  # prefix of the file. Callers are expected to treat truncation as a failure.
  class Importer
    DEFAULT_PATH = Rails.root.join("db/wine_references/xwines_sample_100.csv").freeze
    BATCH_SIZE = 500

    # Source "Type" values are either a plain colour or a slash-separated
    # refinement ("Dessert/Port"), so each segment is looked up in turn and the
    # first known one wins. Unknown types leave the colour blank rather than
    # guessing.
    COLOR_BY_TYPE = {
      "red" => "red",
      "white" => "white",
      "rose" => "rose",
      "rosé" => "rose",
      "sparkling" => "sparkling",
      "dessert" => "dessert",
      "port" => "dessert"
    }.freeze

    UPSERT_COLUMNS = %i[external_id name producer region country grape_variety color abv
                        vintages food_pairings].freeze

    Summary = Struct.new(:imported, :skipped, :error, keyword_init: true) do
      # True when parsing stopped before the end of the file, i.e. the counts
      # describe only the rows up to the break point.
      def truncated?
        error.present?
      end

      def to_s
        counts = "imported #{imported}, skipped #{skipped}"
        return counts unless truncated?

        "#{counts} — TRUNCATED: parsing stopped early (#{error}); rows after that point were NOT imported"
      end
    end

    def self.call(path = DEFAULT_PATH)
      new(path).call
    end

    def initialize(path = DEFAULT_PATH)
      @path = path.to_s
    end

    def call
      raise ArgumentError, "CSV not found: #{path}" unless File.exist?(path)

      # Counting upserted rows would double-count an external_id that appears in
      # two batches, so track the distinct ids seen across the whole run.
      @imported_ids = Set.new
      @skipped = 0
      @error = nil
      batch = []

      each_row do |row|
        attributes = build_attributes(row)
        if attributes.nil?
          @skipped += 1
          next
        end

        batch << attributes
        flush(batch) if batch.size >= BATCH_SIZE
      end

      flush(batch)
      Summary.new(imported: @imported_ids.size, skipped: @skipped, error: @error)
    end

    private

    attr_reader :path

    # liberal_parsing keeps stray quotes inside a field from raising, and the
    # per-row rescue contains anything else (encoding, ragged rows) to that row.
    def each_row
      CSV.foreach(path, headers: true, liberal_parsing: true) do |row|
        yield row
      rescue StandardError => e
        Rails.logger.warn("[wine_references] skipped row: #{e.class}: #{e.message}")
        @skipped += 1
      end
    rescue CSV::MalformedCSVError => e
      # Unrecoverable: the parser cannot resynchronise, so the rest of the file
      # is gone. Record it so the caller can fail loudly instead of trusting a
      # count that only covers the lines before the break.
      Rails.logger.error("[wine_references] import stopped early: #{e.message}")
      @error = e.message
    end

    def flush(batch)
      return if batch.empty?

      # A duplicate WineID inside one statement would make Postgres reject the
      # whole upsert ("cannot affect row a second time"), so the last occurrence
      # wins per batch.
      rows = batch.index_by { |attributes| attributes[:external_id] }.values
      WineReference.upsert_all(rows, unique_by: :external_id)
      @imported_ids.merge(rows.map { |attributes| attributes[:external_id] })
      batch.clear
    end

    def build_attributes(row)
      external_id = row["WineID"].to_s.strip
      name = row["WineName"].to_s.strip
      return nil if external_id.blank? || name.blank?

      {
        external_id: external_id,
        name: name,
        producer: presence_of(row["WineryName"]),
        region: presence_of(row["RegionName"]),
        country: presence_of(row["Country"]),
        grape_variety: presence_of(PythonList.parse(row["Grapes"]).join(", ")),
        color: color_for(row["Type"]),
        abv: parse_decimal(row["ABV"]),
        vintages: PythonList.integers(row["Vintages"]),
        food_pairings: PythonList.parse(row["Harmonize"])
      }
    end

    def color_for(type)
      type.to_s.downcase.split("/").filter_map { |segment| COLOR_BY_TYPE[segment.strip] }.first
    end

    def parse_decimal(value)
      Float(value.to_s.strip, exception: false)
    end

    def presence_of(value)
      value.to_s.strip.presence
    end
  end
end
