class CreateWines < ActiveRecord::Migration[8.1]
  def change
    create_table :wines do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :producer
      t.string :grape_variety
      t.integer :vintage_year
      t.integer :color, null: false, default: 0
      t.string :region
      t.text :description
      t.integer :bottle_size_ml, null: false, default: 750
      t.integer :price_bottle_cents
      t.integer :price_75ml_cents
      t.integer :price_100ml_cents
      t.integer :price_125ml_cents
      t.integer :price_150ml_cents
      t.integer :available_glasses, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :wines, [:restaurant_id, :position]
    add_index :wines, [:restaurant_id, :color]
  end
end
