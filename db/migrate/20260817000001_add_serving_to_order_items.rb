class AddServingToOrderItems < ActiveRecord::Migration[8.1]
  def change
    # 0 = glass (today's only serving; matches OrderItem's enum), 1 = bottle.
    add_column :order_items, :serving, :integer, default: 0, null: false

    # A bottle order item carries no glass_size_ml, so the column can no
    # longer be NOT NULL. Relaxing a constraint is safe in the same deploy as
    # code that still always sets it.
    change_column_null :order_items, :glass_size_ml, true

    # DB-level backstop mirroring OrderItem's serving-conditional validation,
    # so bulk imports / raw SQL / update_column cannot persist a glass line
    # with no size or a bottle line with one. Follows the wines table's
    # t.check_constraint precedent (see 20260705004500).
    add_check_constraint :order_items,
      "(serving = 0 AND glass_size_ml IS NOT NULL) OR (serving = 1 AND glass_size_ml IS NULL)",
      name: "order_items_serving_glass_size"
  end
end
