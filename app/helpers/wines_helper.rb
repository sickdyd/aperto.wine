module WinesHelper
  BOTTLE_SHAPES = {
    "red" => "bordeaux",
    "white" => "burgundy",
    "rose" => "burgundy",
    "sparkling" => "champagne",
    "dessert" => "flute"
  }.freeze

  LIQUID_COLORS = {
    "red" => "#722F37",
    "white" => "#F5E6B8",
    "rose" => "#E8A0A0",
    "sparkling" => "#F0DC82",
    "dessert" => "#D4A840"
  }.freeze

  def bottle_icon(wine, bottle: nil, size: :md)
    shape = bottle_shape_for(wine.color)
    fill = bottle_fill_percent(wine, bottle)
    sealed = bottle&.sealed? || bottle.nil?
    color = wine_liquid_color(wine.color)

    render "shared/bottles/bottle",
      shape: shape,
      fill_percent: fill,
      sealed: sealed,
      wine_color: color,
      size: size
  end

  def bottle_shape_for(color)
    BOTTLE_SHAPES.fetch(color.to_s, "bordeaux")
  end

  def wine_liquid_color(color)
    LIQUID_COLORS.fetch(color.to_s, "#722F37")
  end

  def bottle_fill_percent(wine, bottle)
    return 100 if bottle.nil? || bottle.sealed?
    return 0 if bottle.empty?

    total = wine.suggested_glasses(125)
    return 100 if total.zero?

    remaining = bottle.respond_to?(:glasses_remaining) ? (bottle.glasses_remaining || 0) : 0
    ((remaining.to_f / total) * 100).clamp(0, 100).round
  end
end
