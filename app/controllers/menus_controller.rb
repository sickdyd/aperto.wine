class MenusController < ApplicationController
  def show
    @restaurant = Restaurant.active.find(params[:id])
    @wines = @restaurant.wines.active.by_position
  end
end
