class AddFeaturedIndexToWines < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Featured wines are queried per restaurant for promotion on the menu.
    # Built CONCURRENTLY so the index build does not block writes to `wines`.
    add_index :wines, %i[restaurant_id position],
              where: "featured",
              name: "index_wines_on_restaurant_id_and_position_where_featured",
              algorithm: :concurrently
  end
end
