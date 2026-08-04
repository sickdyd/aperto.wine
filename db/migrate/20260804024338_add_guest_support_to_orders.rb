class AddGuestSupportToOrders < ActiveRecord::Migration[8.1]
  # Migration-local AR class so this migration keeps working even after the
  # real Order model's validations change. Never reference app/models/order.rb
  # from here.
  class MigrationOrder < ActiveRecord::Base
    self.table_name = "orders"
  end

  def up
    change_column_null :orders, :customer_id, true
    add_column :orders, :guest_name, :string
    add_column :orders, :public_token, :string

    MigrationOrder.reset_column_information
    MigrationOrder.find_each do |order|
      order.update_column(:public_token, unique_token)
    end

    change_column_null :orders, :public_token, false
    add_index :orders, :public_token, unique: true
  end

  def down
    # This will raise if any order has a null customer_id (i.e. a guest
    # order was placed). That is expected: a guest order has no customer
    # to restore, so this migration cannot be rolled back once guest
    # orders exist.
    remove_index :orders, :public_token
    remove_column :orders, :public_token
    remove_column :orders, :guest_name
    change_column_null :orders, :customer_id, false
  end

  private

  def unique_token
    loop do
      token = SecureRandom.base58(24)
      break token unless MigrationOrder.exists?(public_token: token)
    end
  end
end
