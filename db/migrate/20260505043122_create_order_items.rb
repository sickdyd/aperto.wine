class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :wine, null: false, foreign_key: true
      t.integer :glass_size_ml, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false

      t.timestamps
    end
  end
end
