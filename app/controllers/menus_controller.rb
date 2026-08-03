class MenusController < ApplicationController
  before_action :set_restaurant_and_table

  def show
    # The public menu shows every enabled curated list, grouped by wine colour
    # within each list. Availability is always driven by the wines/bottles,
    # never by list membership.
    @wine_lists = @restaurant.wine_lists.active.by_position
                             .includes(wine_list_items: { wine: :wine_bottles })
  end

  private

  # The menu is reachable two ways: the generic restaurant QR (/menu/:id) and
  # a per-table QR (/t/:table_token). A table token also pins the diner's table
  # in the session so a future order can be attributed to it. A token whose
  # table was deactivated still shows the menu, just without table context —
  # stale printed QRs must never break.
  def set_restaurant_and_table
    if params[:table_token].present?
      table = RestaurantTable.find_by!(token: params[:table_token])
      @restaurant = Restaurant.active.find(table.restaurant_id)

      if table.active?
        @restaurant_table = table
        remember_table(@restaurant_table)
      end
    else
      @restaurant = Restaurant.active.find(params[:id])
    end
  end

  def remember_table(table)
    tokens = session[:table_tokens] || {}
    session[:table_tokens] = tokens.merge(table.restaurant_id.to_s => table.token)
  end
end
