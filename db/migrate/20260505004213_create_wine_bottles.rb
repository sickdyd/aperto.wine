class CreateWineBottles < ActiveRecord::Migration[8.1]
  def change
    create_table :wine_bottles do |t|
      t.references :wine, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :opened_at
      t.integer :glasses_remaining, null: false, default: 0

      t.timestamps
    end

    add_index :wine_bottles, [ :wine_id, :status ]
  end
end
