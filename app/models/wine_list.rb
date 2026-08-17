class WineList < ApplicationRecord
  include Sluggable

  belongs_to :restaurant
  has_many :wine_list_items, dependent: :destroy
  has_many :wines, through: :wine_list_items

  # The slug follows the name, so a rename gives a matching URL. Safe to do
  # here — unlike the restaurant slug, no QR code points at a list slug: they
  # all point at the restaurant, which redirects to whichever list is
  # published. Clearing it lets Sluggable regenerate it.
  before_validation :reset_slug_on_rename, prepend: true

  validates :name, presence: true, length: { maximum: 100 }
  validates :season, length: { maximum: 50 }

  scope :published, -> { where(published: true) }
  scope :by_position, -> { order(:position, :name) }

  # Makes this the restaurant's one public list. Unpublishing the incumbent
  # first is what keeps the partial unique index satisfied, and the
  # transaction is what stops a failure midway leaving the restaurant with no
  # published list at all.
  def publish!
    transaction do
      restaurant.wine_lists.published.where.not(id: id).update_all(published: false, updated_at: Time.current)
      update!(published: true)
    end
  end

  private

  def reset_slug_on_rename
    self.slug = nil if persisted? && name_changed?
  end

  def slug_source
    name
  end

  def slug_fallback
    "list-#{SecureRandom.hex(4)}"
  end

  def slug_scope
    return nil if restaurant_id.blank?

    WineList.where(restaurant_id: restaurant_id)
  end
end
