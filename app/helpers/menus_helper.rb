module MenusHelper
  # Curated lists paired with their items grouped by wine colour, in wine
  # colour enum order (see Wine::color). Within a colour, items stay sorted by
  # [position, id], mirroring the list's flat position sequence. Colours with
  # no items are omitted; lists left with no items at all are dropped.
  def renderable_wine_lists(wine_lists)
    wine_lists.filter_map do |list|
      items = list.wine_list_items
                  .select { |item| item.wine.active? }
                  .sort_by { |item| [ item.position, item.id ] }
      next if items.empty?

      by_colour = items.group_by { |item| item.wine.color }
      colour_groups = Wine.colors.keys.filter_map do |colour|
        [ colour, by_colour[colour] ] if by_colour.key?(colour)
      end

      [ list, colour_groups ]
    end
  end

  # [dom_id, label] pairs for the jump-nav chips — one per rendered list x
  # colour section, in page order. Ids derive from record ids / enum keys,
  # never display names. Labels include the list name only when more than one
  # list renders, so chips stay unambiguous.
  def menu_nav_sections(rendered_lists)
    multiple_lists = rendered_lists.size > 1

    rendered_lists.flat_map do |list, colour_groups|
      colour_groups.map do |colour, _items|
        colour_name = t("owner.wines.colors.#{colour}")
        label = multiple_lists ? "#{list.name} · #{colour_name}" : colour_name
        [ "list-#{list.id}-#{colour}", label ]
      end
    end
  end
end
