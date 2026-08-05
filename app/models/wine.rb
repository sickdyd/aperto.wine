class Wine < ApplicationRecord
  belongs_to :restaurant
  has_many :wine_bottles, dependent: :destroy
  has_many :wine_list_items, dependent: :destroy
  has_many :wine_lists, through: :wine_list_items
  has_one_attached :label_image

  enum :color, { red: 0, white: 1, rose: 2, sparkling: 3, dessert: 4 }

  GLASS_SIZES = [ 75, 100, 125, 150 ].freeze
  TASTING_SCALE = (0..5).freeze
  TASTING_ATTRIBUTES = %i[tannins acidity sweetness body].freeze
  CERTIFICATION_LABELS = %i[organic natural_wine vegan biodynamic].freeze
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_IMAGE_BYTES = 5.megabytes
  MAX_AROMAS = 20
  MAX_FOOD_PAIRINGS = 20

  validates :name, presence: true
  validates :bottle_size_ml, numericality: { greater_than: 0 }
  validates :available_glasses, numericality: { greater_than_or_equal_to: 0 }
  validates :abv,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  # Bounded with greater_than_or_equal_to/less_than_or_equal_to rather than
  # `in: TASTING_SCALE` so the error message carries a plain integer bound
  # instead of interpolating the raw Ruby Range ("0..5") into user copy.
  validates(*TASTING_ATTRIBUTES,
            numericality: { only_integer: true,
                            greater_than_or_equal_to: TASTING_SCALE.min,
                            less_than_or_equal_to: TASTING_SCALE.max },
            allow_nil: true)
  validates :style, :short_description, length: { maximum: 500 }, allow_blank: true
  validates :image_url,
            format: { with: %r{\Ahttps?://\S+\z}i, message: :invalid_url },
            length: { maximum: 2048 },
            allow_blank: true
  validates :aromas, length: { maximum: MAX_AROMAS }
  validates :food_pairings, length: { maximum: MAX_FOOD_PAIRINGS }
  validates :label_image,
            content_type: IMAGE_CONTENT_TYPES,
            size: { less_than: MAX_IMAGE_BYTES }

  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }
  scope :by_position, -> { order(:color, :position, :name) }

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
