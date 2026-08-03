# Read-only catalogue of real-world wines, imported from the public-domain
# X-Wines dataset (CC0-1.0). It exists solely to power the owner type-ahead;
# nothing here belongs to a restaurant.
class WineReference < ApplicationRecord
  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :color, inclusion: { in: Wine.colors.keys }, allow_nil: true

  def latest_vintage
    vintages.compact.max
  end
end
