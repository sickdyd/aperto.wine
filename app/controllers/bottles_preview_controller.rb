class BottlesPreviewController < ApplicationController
  # Temporary controller for previewing bottle SVGs during development.
  # Remove after bottle design is finalized.

  def index
    @shapes = %w[bordeaux burgundy flute champagne]
    @fill_levels = [100, 75, 50, 25, 10, 0]
    @wine_colors = {
      "bordeaux" => "#722F37",
      "burgundy" => "#F5E6B8",
      "flute" => "#D4A840",
      "champagne" => "#F0DC82"
    }
    @shape_labels = {
      "bordeaux" => "Bordeaux (Red)",
      "burgundy" => "Burgundy (White/Rose)",
      "flute" => "Flute (Dessert)",
      "champagne" => "Champagne (Sparkling)"
    }
  end
end
