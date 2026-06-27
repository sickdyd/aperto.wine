class CreateWineLists < ActiveRecord::Migration[8.1]
  def change
    create_table :wine_lists do |t|
      t.references :restaurant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :season
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :wine_lists, [ :restaurant_id, :position ]
  end
end
