class AddAllWinesListActiveToRestaurants < ActiveRecord::Migration[8.1]
  def change
    add_column :restaurants, :all_wines_list_active, :boolean, null: false, default: true
  end
end
