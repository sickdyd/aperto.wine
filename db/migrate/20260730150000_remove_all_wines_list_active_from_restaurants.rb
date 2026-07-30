class RemoveAllWinesListActiveFromRestaurants < ActiveRecord::Migration[8.1]
  def change
    remove_column :restaurants, :all_wines_list_active, :boolean, default: true, null: false
  end
end
