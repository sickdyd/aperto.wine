class MenusController < ApplicationController
  def show
    @restaurant = Restaurant.active.find(params[:id])

    # Curated lists take over the menu when the restaurant has published any;
    # otherwise the view falls back to the full wine list. Availability is
    # always driven by the wines/bottles, never by list membership.
    @wine_lists = @restaurant.wine_lists.active.by_position
                             .includes(wine_list_items: { wine: :wine_bottles })
    @wines = @restaurant.wines.active.by_position.includes(:wine_bottles)
  end
end
