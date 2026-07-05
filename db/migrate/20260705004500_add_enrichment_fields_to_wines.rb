class AddEnrichmentFieldsToWines < ActiveRecord::Migration[8.1]
  def change
    change_table :wines, bulk: true do |t|
      # Technical — percentage 0..100, decimal(5,2) so 100.00 fits without overflow.
      t.decimal :abv, precision: 5, scale: 2

      # Certification labels (owner self-declared)
      t.boolean :organic, default: false, null: false
      t.boolean :natural_wine, default: false, null: false
      t.boolean :vegan, default: false, null: false
      t.boolean :biodynamic, default: false, null: false

      # Tasting profile (0-5 scale)
      t.integer :tannins, limit: 2
      t.integer :acidity, limit: 2
      t.integer :sweetness, limit: 2
      t.integer :body, limit: 2

      # Structured descriptive content
      t.string :aromas, array: true, default: [], null: false
      t.string :food_pairings, array: true, default: [], null: false
      t.string :style
      t.string :short_description

      # Presentation.
      # image_url: external reference (e.g. Wine-Searcher CDN), never fetched
      #   server-side without SSRF guards. label_image (Active Storage) is the
      #   owner-uploaded label photo and is the canonical image when present.
      t.string :image_url

      # featured: restaurant-curated highlight (promoted on the menu).
      # favorite: restaurant staff pick, distinct from featured placement.
      t.boolean :featured, default: false, null: false
      t.boolean :favorite, default: false, null: false
    end

    # Back the Ruby validations with DB-level guards so bulk imports / raw SQL /
    # update_columns cannot persist out-of-range values.
    add_check_constraint :wines, "abv IS NULL OR (abv >= 0 AND abv <= 100)", name: "wines_abv_range"
    add_check_constraint :wines, "tannins IS NULL OR (tannins BETWEEN 0 AND 5)", name: "wines_tannins_range"
    add_check_constraint :wines, "acidity IS NULL OR (acidity BETWEEN 0 AND 5)", name: "wines_acidity_range"
    add_check_constraint :wines, "sweetness IS NULL OR (sweetness BETWEEN 0 AND 5)", name: "wines_sweetness_range"
    add_check_constraint :wines, "body IS NULL OR (body BETWEEN 0 AND 5)", name: "wines_body_range"
  end
end
