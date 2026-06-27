class CreateWineListItems < ActiveRecord::Migration[8.1]
  def change
    create_table :wine_list_items do |t|
      # index: false — the composite indexes below both lead with wine_list_id,
      # so the standalone single-column index from t.references is redundant.
      t.references :wine_list, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :wine, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :wine_list_items, [ :wine_list_id, :wine_id ], unique: true
    add_index :wine_list_items, [ :wine_list_id, :position ]
  end
end
