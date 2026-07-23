module MenusHelper
  # Curated lists paired with the items the menu will actually render
  # (active wines only, in list order). Lists left with no items are dropped.
  def renderable_wine_lists(wine_lists)
    wine_lists.filter_map do |list|
      items = list.wine_list_items
                  .select { |item| item.wine.active? }
                  .sort_by { |item| [ item.position, item.id ] }
      [ list, items ] if items.any?
    end
  end

  # [dom_id, label] pairs for the jump-nav chips — one per rendered section,
  # mirroring page order: curated lists first, then the All Wines color groups.
  # Ids derive from record ids / enum keys, never display names.
  def menu_nav_sections(rendered_lists, color_groups)
    list_sections = rendered_lists.map { |list, _items| [ "list-#{list.id}", list.name ] }
    color_sections = color_groups.keys.map { |color| [ "color-#{color}", t("owner.wines.colors.#{color}") ] }
    list_sections + color_sections
  end
end
