module Owner
  class WinesController < BaseController
    before_action :set_restaurant
    before_action :set_wine, only: %i[edit update destroy]

    def index
      @wines = @restaurant.wines.by_position
    end

    def new
      @wine = @restaurant.wines.build(bottle_size_ml: 750)
    end

    def create
      @wine = @restaurant.wines.build(wine_params)

      if @wine.save
        redirect_to owner_restaurant_wines_path(@restaurant), notice: t("owner.wines.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @wine.update(wine_params)
        redirect_to owner_restaurant_wines_path(@restaurant), notice: t("owner.wines.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @wine.destroy!
      redirect_to owner_restaurant_wines_path(@restaurant), notice: t("owner.wines.deleted")
    end

    private

    def set_restaurant
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
    end

    def set_wine
      @wine = @restaurant.wines.find(params[:id])
    end

    def wine_params
      params.require(:wine).permit(
        :name, :producer, :grape_variety, :vintage_year, :color,
        :region, :description, :bottle_size_ml,
        :price_bottle_cents, :price_75ml_cents, :price_100ml_cents,
        :price_125ml_cents, :price_150ml_cents,
        :available_glasses, :position, :active
      )
    end
  end
end
