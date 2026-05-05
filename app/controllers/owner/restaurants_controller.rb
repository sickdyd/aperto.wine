module Owner
  class RestaurantsController < BaseController
    before_action :set_restaurant, only: %i[show edit update destroy]

    def index
      @restaurants = current_user.restaurants.order(:name)
    end

    def show
    end

    def new
      @restaurant = current_user.restaurants.build
    end

    def create
      @restaurant = current_user.restaurants.build(restaurant_params)

      if @restaurant.save
        redirect_to owner_restaurant_path(@restaurant), notice: t("owner.restaurants.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @restaurant.update(restaurant_params)
        redirect_to owner_restaurant_path(@restaurant), notice: t("owner.restaurants.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @restaurant.destroy!
      redirect_to owner_restaurants_path, notice: t("owner.restaurants.deleted")
    end

    private

    def set_restaurant
      @restaurant = current_user.restaurants.find(params[:id])
    end

    def restaurant_params
      params.require(:restaurant).permit(:name, :address, :description, :latitude, :longitude, :proximity_radius_meters, :active)
    end
  end
end
