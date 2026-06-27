class MenusController < ApplicationController
  def show
    @restaurant = Restaurant.active.find(params[:id])

    # The public menu shows every enabled list. Custom curated lists are
    # explicitly published by the owner; the default "All Wines" list reflects
    # every available wine and is toggled via a flag on the restaurant.
    # Availability is always driven by the wines/bottles, never by membership.
    @wine_lists = @restaurant.wine_lists.active.by_position
                             .includes(wine_list_items: { wine: :wine_bottles })
    @show_all_wines = @restaurant.all_wines_list_active?
    @wines = @restaurant.wines.active.by_position.includes(:wine_bottles)
  end
end
