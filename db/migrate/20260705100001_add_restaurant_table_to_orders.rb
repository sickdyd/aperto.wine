class AddRestaurantTableToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :restaurant_table, foreign_key: { on_delete: :nullify }
  end
end
