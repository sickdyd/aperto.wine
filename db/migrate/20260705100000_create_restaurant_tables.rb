class CreateRestaurantTables < ActiveRecord::Migration[8.1]
  def change
    create_table :restaurant_tables do |t|
      t.references :restaurant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :area
      t.string :token, null: false
      t.integer :position, default: 0, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :restaurant_tables, :token, unique: true
    add_index :restaurant_tables, [ :restaurant_id, :area, :position ]
    # DB-level backstop for the model's case-insensitive name uniqueness
    # (scoped to restaurant + area). COALESCE folds NULL areas together,
    # since Postgres treats each NULL as distinct in unique indexes.
    add_index :restaurant_tables,
              "restaurant_id, COALESCE(area, ''), lower(name)",
              unique: true,
              name: "index_restaurant_tables_on_restaurant_area_name"
  end
end
