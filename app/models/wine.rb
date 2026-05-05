class Wine < ApplicationRecord
  belongs_to :restaurant
  has_many :wine_bottles, dependent: :destroy

  enum :color, { red: 0, white: 1, rose: 2, sparkling: 3, dessert: 4 }

  validates :name, presence: true
  validates :bottle_size_ml, numericality: { greater_than: 0 }
  validates :available_glasses, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :by_position, -> { order(:color, :position, :name) }

  GLASS_SIZES = [ 75, 100, 125, 150 ].freeze

  def suggested_glasses(glass_size_ml)
    return 0 unless glass_size_ml.positive?

    (bottle_size_ml / glass_size_ml).floor
  end

  def price_for_glass(glass_size_ml)
    case glass_size_ml
    when 75 then price_75ml_cents
    when 100 then price_100ml_cents
    when 125 then price_125ml_cents
    when 150 then price_150ml_cents
    end
  end

  def available?
    active? && available_glasses.positive?
  end
end
