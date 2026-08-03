class CreateWineReferences < ActiveRecord::Migration[8.1]
  def change
    # Trigram indexes back the type-ahead: they are what makes an unanchored
    # `ILIKE '%query%'` on a six-figure reference table fast enough to run on
    # every keystroke.
    enable_extension "pg_trgm"

    create_table :wine_references do |t|
      # WineID from the source dataset. Unique so re-importing upserts instead
      # of duplicating.
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :producer
      t.string :region
      t.string :country
      t.string :grape_variety
      # One of Wine.colors (red/white/rose/sparkling/dessert), or NULL when the
      # source type has no equivalent.
      t.string :color
      t.decimal :abv, precision: 5, scale: 2
      t.integer :vintages, array: true, default: [], null: false
      t.string :food_pairings, array: true, default: [], null: false

      t.timestamps
    end

    add_index :wine_references, :external_id, unique: true
    add_index :wine_references, :name, using: :gin, opclass: :gin_trgm_ops,
              name: "index_wine_references_on_name_trgm"
    add_index :wine_references, :producer, using: :gin, opclass: :gin_trgm_ops,
              name: "index_wine_references_on_producer_trgm"
  end
end
