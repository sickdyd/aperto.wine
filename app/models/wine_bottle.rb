class WineBottle < ApplicationRecord
  belongs_to :wine

  enum :status, { sealed: 0, open: 1, empty: 2 }

  scope :current, -> { where(status: [ :sealed, :open ]) }

  def open!
    update!(status: :open, opened_at: Time.current)
  end
end
