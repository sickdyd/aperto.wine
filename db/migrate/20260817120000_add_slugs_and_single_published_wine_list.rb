# Public menus move from numeric ids to slugs, and a restaurant publishes
# exactly one wine list at a time.
#
# The backfill deliberately reimplements slug generation rather than calling
# Restaurant/WineList: a migration must keep working after the models change
# underneath it.
class AddSlugsAndSinglePublishedWineList < ActiveRecord::Migration[8.1]
  # Top-level path segments the public routes already own. A restaurant slug
  # equal to one of these would be shadowed by the route declared above it.
  RESERVED_RESTAURANT_SLUGS = %w[
    menu t cart orders sign_in sign_up sign_out owner up rails_icons en it
  ].freeze

  class MigrationRestaurant < ActiveRecord::Base
    self.table_name = "restaurants"
  end

  class MigrationWineList < ActiveRecord::Base
    self.table_name = "wine_lists"
  end

  def up
    add_column :restaurants, :slug, :string
    add_column :wine_lists, :slug, :string
    rename_column :wine_lists, :active, :published
    # "active" defaulted to true, which under the partial unique index below
    # would make every second list a restaurant creates collide. Publishing is
    # now an explicit act, so new lists start unpublished.
    change_column_default :wine_lists, :published, from: true, to: false

    backfill_restaurant_slugs
    backfill_wine_list_slugs
    collapse_to_one_published_list_per_restaurant

    change_column_null :restaurants, :slug, false
    change_column_null :wine_lists, :slug, false

    add_index :restaurants, :slug, unique: true
    add_index :wine_lists, %i[restaurant_id slug], unique: true
    # The single-published invariant, enforced by Postgres rather than by
    # application code alone: a partial unique index over restaurant_id that
    # only covers published rows.
    add_index :wine_lists, :restaurant_id,
              unique: true,
              where: "published",
              name: "index_wine_lists_on_one_published_per_restaurant"
  end

  def down
    remove_index :wine_lists, name: "index_wine_lists_on_one_published_per_restaurant"
    remove_index :wine_lists, %i[restaurant_id slug]
    remove_index :restaurants, :slug

    change_column_default :wine_lists, :published, from: false, to: true
    rename_column :wine_lists, :published, :active
    remove_column :wine_lists, :slug
    remove_column :restaurants, :slug
  end

  private

  def backfill_restaurant_slugs
    taken = []

    MigrationRestaurant.order(:id).each do |restaurant|
      slug = unique_slug(
        base: slug_base(restaurant.name, fallback: "restaurant-#{restaurant.id}"),
        taken: taken,
        reserved: RESERVED_RESTAURANT_SLUGS
      )
      taken << slug
      restaurant.update_columns(slug: slug)
    end
  end

  def backfill_wine_list_slugs
    MigrationWineList.order(:id).group_by(&:restaurant_id).each_value do |lists|
      taken = []

      lists.each do |list|
        slug = unique_slug(
          base: slug_base(list.name, fallback: "list-#{list.id}"),
          taken: taken,
          reserved: []
        )
        taken << slug
        list.update_columns(slug: slug)
      end
    end
  end

  # Several lists per restaurant could be active before this migration. Keep
  # the one the owner sees first (lowest position, then lowest id) and retire
  # the rest, so the new partial unique index can be created.
  def collapse_to_one_published_list_per_restaurant
    MigrationWineList.where(published: true).group_by(&:restaurant_id).each_value do |lists|
      next if lists.one?

      keeper = lists.min_by { |list| [ list.position, list.id ] }
      MigrationWineList.where(id: lists.map(&:id) - [ keeper.id ]).update_all(published: false)
    end
  end

  def slug_base(name, fallback:)
    candidate = name.to_s.parameterize
    candidate.presence || fallback
  end

  def unique_slug(base:, taken:, reserved:)
    candidate = base
    suffix = 1

    while taken.include?(candidate) || reserved.include?(candidate)
      suffix += 1
      candidate = "#{base}-#{suffix}"
    end

    candidate
  end
end
