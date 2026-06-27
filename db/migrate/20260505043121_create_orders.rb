class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.integer :total_amount_cents, null: false, default: 0

      t.timestamps
    end

    add_index :orders, [ :restaurant_id, :status ]
    add_index :orders, [ :customer_id, :status ]
  end
end
