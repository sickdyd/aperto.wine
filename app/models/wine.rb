class Wine < ApplicationRecord
  belongs_to :restaurant
  has_many :wine_bottles, dependent: :destroy
  has_many :wine_list_items, dependent: :destroy
  has_many :wine_lists, through: :wine_list_items
  has_one_attached :label_image

  enum :color, { red: 0, white: 1, rose: 2, sparkling: 3, dessert: 4 }

  GLASS_SIZES = [ 75, 100, 125, 150 ].freeze
  SERVINGS = %w[glass bottle].freeze
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

  # "Has a glass to pour right now." This used to be #available?'s whole
  # meaning; it was renamed once #available? widened to cover bottles too.
  def glasses_available?
    active? && available_glasses.positive?
  end

  # There is no bottle stock column — a positive bottle price is the owner's
  # signal that whole bottles are sold. A wine can be bottle-available with
  # zero glasses left; that's the point of the feature. Zero and nil both
  # mean "not offered", matching how Cart#positive_price? already treats
  # glass prices.
  def bottle_available?
    active? && price_bottle_cents.to_i.positive?
  end

  def price_for(serving:, glass_size_ml: nil)
    case serving.to_s
    when "bottle" then price_bottle_cents
    when "glass" then price_for_glass(glass_size_ml)
    end
  end

  def available_for?(serving:, glass_size_ml: nil)
    case serving.to_s
    when "bottle" then bottle_available?
    when "glass" then glasses_available?
    else false
    end
  end

  # "Orderable in some form" — by the glass, by the bottle, or both. This is
  # what the menu's sold-out tag means. It is NOT "has a glass to pour": a
  # caller that only ever offers glasses (i.e. hasn't been made
  # serving-aware yet) must use #glasses_available? instead, or a wine with
  # zero glasses but a bottle price will read as available for glass pours
  # it cannot actually serve.
  def available?
    glasses_available? || bottle_available?
  end
end
