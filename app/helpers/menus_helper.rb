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

  # The menu's filter chips, derived from the wines actually on
  # `rendered_lists` (never a hardcoded list) — region and grape are
  # deliberately excluded here; see the view comment where this is rendered
  # for why.
  #
  # Returns { groups:, wine_values: }:
  #   groups       - [{ name:, label:, options: [{ value:, label: }] }], one
  #                   per facet worth showing. A facet with fewer than two
  #                   distinct values earns no row and is left out entirely —
  #                   a chip row where every chip matches everything is noise.
  #   wine_values  - { wine => { facet_name => "value1 value2" } }, one entry
  #                  per wine that takes a value on at least one rendered
  #                  facet. The view stamps these onto each wine row's
  #                  data-facet-<name> attributes; list_filter_controller.js
  #                  reads them back to filter.
  def menu_filter_facets(rendered_lists)
    wines = rendered_lists.flat_map { |_list, colour_groups|
      colour_groups.flat_map { |_colour, items| items.map(&:wine) }
    }.uniq

    groups = [
      menu_color_facet(wines),
      menu_serving_facet(wines),
      menu_certification_facet(wines),
      menu_price_band_facet(wines)
    ].compact

    wine_values = wines.index_with { |wine|
      groups.filter_map { |group|
        value = group[:wine_values][wine]
        [ group[:name], value ] if value.present?
      }.to_h
    }.reject { |_wine, values| values.empty? }

    { groups: groups.map { |group| group.except(:wine_values) }, wine_values: wine_values }
  end

  private

  def menu_color_facet(wines)
    present = Wine.colors.keys & wines.map(&:color).uniq
    return nil if present.size < 2

    {
      name: "color",
      label: t("menu.filters.color_label"),
      options: present.map { |colour| { value: colour, label: t("owner.wines.colors.#{colour}") } },
      wine_values: wines.index_with(&:color)
    }
  end

  def menu_serving_facet(wines)
    return nil if wines.none?(&:glasses_available?) || wines.none?(&:bottle_available?)

    wine_values = wines.index_with { |wine|
      [ ("glass" if wine.glasses_available?), ("bottle" if wine.bottle_available?) ].compact.join(" ")
    }.reject { |_wine, value| value.empty? }

    {
      name: "serving",
      label: t("menu.filters.serving_label"),
      options: [
        { value: "glass", label: t("menu.filters.serving.glass") },
        { value: "bottle", label: t("menu.filters.serving.bottle") }
      ],
      wine_values: wine_values
    }
  end

  def menu_certification_facet(wines)
    present = Wine::CERTIFICATION_LABELS.select { |cert| wines.any? { |wine| wine.public_send(:"#{cert}?") } }
    return nil if present.size < 2

    wine_values = wines.index_with { |wine|
      present.select { |cert| wine.public_send(:"#{cert}?") }.join(" ")
    }.reject { |_wine, value| value.empty? }

    {
      name: "certification",
      label: t("menu.filters.certification_label"),
      options: present.map { |cert| { value: cert.to_s, label: t("shared.certifications.#{cert}") } },
      wine_values: wine_values
    }
  end

  # Three bands, split by rank (tertiles of the rendered set's own lowest
  # offered price per wine) rather than by a hardcoded currency threshold —
  # see #menu_lowest_offered_price_cents for what "lowest offered" means.
  # Splitting by rank rather than by value keeps the three bands close to
  # equally populated regardless of how the prices are distributed; a
  # value-threshold split degenerates on small or skewed sets (e.g. three
  # wines' cutoffs landing on the same value would leave the top band empty
  # every time). A set with fewer than three distinctly-priced wines renders
  # no price facet at all, and if the resulting split still leaves fewer than
  # two bands populated (an extreme skew — most wines clustered at one end),
  # the facet is dropped rather than shown with a single, all-matching chip.
  def menu_price_band_facet(wines)
    priced = wines.index_with { |wine| menu_lowest_offered_price_cents(wine) }.compact
    return nil if priced.values.uniq.size < 3

    sorted = priced.values.sort
    last_index = sorted.size - 1
    boundary_low = sorted[last_index / 3]
    boundary_high = sorted[2 * last_index / 3]

    band_for = lambda do |price|
      if price <= boundary_low then "low"
      elsif price <= boundary_high then "mid"
      else "high"
      end
    end

    wine_values = priced.transform_values(&band_for)
    bands_present = wine_values.values.uniq
    return nil if bands_present.size < 2

    labels = {
      "low" => t("menu.filters.price_band.up_to", amount: format_cents(boundary_low)),
      "mid" => t("menu.filters.price_band.between", low: format_cents(boundary_low), high: format_cents(boundary_high)),
      "high" => t("menu.filters.price_band.over", amount: format_cents(boundary_high))
    }

    {
      name: "price-band",
      label: t("menu.filters.price_band_label"),
      options: %w[low mid high].select { |band| bands_present.include?(band) }.map { |band| { value: band, label: labels[band] } },
      wine_values: wine_values
    }
  end

  # The cheapest way this wine is actually orderable right now — the same
  # bottle/glass prices menus/_wine_row renders, so the price facet never
  # implies a price the diner can't actually pick.
  def menu_lowest_offered_price_cents(wine)
    prices = []
    prices << wine.price_bottle_cents if wine.bottle_available?
    if wine.glasses_available?
      Wine::GLASS_SIZES.each do |size|
        price = wine.price_for_glass(size)
        prices << price if price&.positive?
      end
    end
    prices.min
  end
end
