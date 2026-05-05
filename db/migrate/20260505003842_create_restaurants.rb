class CreateRestaurants < ActiveRecord::Migration[8.1]
  def change
    create_table :restaurants do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :address, null: false
      t.text :description
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.integer :proximity_radius_meters, null: false, default: 200
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
