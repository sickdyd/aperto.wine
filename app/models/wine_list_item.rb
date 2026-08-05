class WineListItem < ApplicationRecord
  belongs_to :wine_list
  belongs_to :wine

  validates :wine_id, uniqueness: { scope: :wine_list_id }
  validate :wine_and_list_share_restaurant

  scope :by_position, -> { order(:position, :id) }

  private

  def wine_and_list_share_restaurant
    return if wine.nil? || wine_list.nil?
    return if wine.restaurant_id == wine_list.restaurant_id

    errors.add(:wine, :wrong_restaurant)
  end
end
