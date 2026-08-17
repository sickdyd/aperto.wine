# Form object that creates a batch of RestaurantTables from a floors ×
# tables-per-floor grid. Floors become the `area` grouping; names follow a
# selected pattern; existing names in the same area are skipped, not errors.
class TableBulkGeneration
  include ActiveModel::Model
  include ActiveModel::Attributes

  NAME_PATTERNS = %w[table_number t_number number_only floor_table].freeze
  MAX_FLOORS = 10
  MAX_TABLES_PER_FLOOR = 100
  MAX_TOTAL = 200

  attribute :floors_count, :integer, default: 1
  attribute :tables_per_floor, :integer, default: 10
  attribute :floor_label, :string
  attribute :name_pattern, :string, default: "table_number"

  attr_accessor :restaurant
  attr_reader :created_count, :skipped_count

  # greater_than_or_equal_to/less_than_or_equal_to rather than `in: 1..MAX` so the
  # error carries a plain integer bound, never a raw "1..10" Ruby Range.
  validates :floors_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_FLOORS }
  validates :tables_per_floor,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_TABLES_PER_FLOOR }
  validates :name_pattern, inclusion: { in: NAME_PATTERNS }
  # RestaurantTable#area max length is 100; area_for appends " #{floor}" (up to " 10" = 3 chars),
  # so floor_label must not exceed 97 to stay within the limit.
  validates :floor_label, length: { maximum: 97 }, allow_blank: true
  validate :floor_label_required_for_multiple_floors
  validate :total_within_cap

  def save
    @created_count = 0
    @skipped_count = 0
    return false unless valid?

    existing = restaurant.restaurant_tables.pluck(:area, :name)
                         .map { |area, name| [ area, name.downcase ] }.to_set

    RestaurantTable.transaction do
      each_table do |area, name|
        if existing.include?([ area, name.downcase ])
          @skipped_count += 1
        else
          begin
            restaurant.restaurant_tables.create!(name:, area:, active: true)
            @created_count += 1
          rescue ActiveRecord::RecordInvalid
            # A duplicate (area, name) committed between the snapshot above and
            # this create's uniqueness check; skip this table. (An insert racing
            # inside the window still hits the DB unique index and 500s — rare
            # enough for an owner-only form that we accept it.)
            @skipped_count += 1
          end
        end
      end
    end
    true
  end

  private

  # The running number is a naming input only. It used to be yielded as a
  # `position` too, but nothing reads that column any more — tables display in
  # (area, name) order — so writing it would have left a value no screen could
  # show and no form could correct.
  def each_table
    (1..floors_count).each do |floor|
      (1..tables_per_floor).each do |number|
        yield area_for(floor), name_for(floor, number)
      end
    end
  end

  def area_for(floor)
    label = floor_label.to_s.strip
    return nil if label.blank?

    floors_count > 1 ? "#{label} #{floor}" : label
  end

  def name_for(floor, number)
    case name_pattern
    when "table_number" then "#{I18n.t('owner.tables.bulk.table_word')} #{number}"
    when "t_number" then "T#{number}"
    when "number_only" then number.to_s
    when "floor_table" then "#{floor}-#{number}"
    end
  end

  def floor_label_required_for_multiple_floors
    return if floors_count.to_i <= 1 || floor_label.to_s.strip.present?

    errors.add(:floor_label, :blank)
  end

  def total_within_cap
    return unless floors_count.to_i >= 1 && tables_per_floor.to_i >= 1
    return if floors_count * tables_per_floor <= MAX_TOTAL

    errors.add(:base, I18n.t("owner.tables.bulk.too_many", max: MAX_TOTAL))
  end
end
