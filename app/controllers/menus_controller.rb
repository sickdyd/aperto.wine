class MenusController < ApplicationController
  include CustomerScoped

  def show
    # The public menu shows every enabled curated list, grouped by wine colour
    # within each list. Availability is always driven by the wines/bottles,
    # never by list membership. @restaurant_table is set by CustomerScoped's
    # set_restaurant directly from this request's own table token, if any —
    # see that method for why it does not use current_table here.
    @wine_lists = @restaurant.wine_lists.active.by_position
                             .includes(wine_list_items: { wine: :wine_bottles })
  end
end
