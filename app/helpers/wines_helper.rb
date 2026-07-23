module WinesHelper
  # Color marker for a wine type. Falls back to red for unknown/nil colors
  # so no unvalidated value ever reaches the class attribute.
  # Pass label: false when visible text next to the dot already names the color.
  def wine_color_dot(color, label: true)
    key = Wine.colors.key?(color.to_s) ? color.to_s : "red"
    dot = tag.span(class: "wine-dot wine-dot-#{key}", aria: { hidden: true })
    return dot unless label

    dot + tag.span(t("owner.wines.colors.#{key}"), class: "sr-only")
  end
end
