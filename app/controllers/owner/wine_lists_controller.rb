module Owner
  class WineListsController < BaseController
    before_action :set_restaurant
    before_action :set_wine_list, only: %i[edit update destroy]

    def index
      @wine_lists = @restaurant.wine_lists.by_position.includes(:wine_list_items)
      @available_wine_count = @restaurant.wines.active.count
    end

    def new
      @wine_list = @restaurant.wine_lists.build(active: true)
    end

    def create
      @wine_list = @restaurant.wine_lists.build(wine_list_params)

      if @wine_list.save
        redirect_to owner_restaurant_wine_lists_path(@restaurant), notice: t("owner.wine_lists.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @wine_list.update(wine_list_params)
        redirect_to owner_restaurant_wine_lists_path(@restaurant), notice: t("owner.wine_lists.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @wine_list.destroy!
      redirect_to owner_restaurant_wine_lists_path(@restaurant), notice: t("owner.wine_lists.deleted")
    end

    # Enable/disable the default "All Wines" list, which always reflects every
    # available wine. Backed by a flag on the restaurant (it has no membership).
    def toggle_all_wines
      @restaurant.update(all_wines_list_active: params[:active].present?)
      redirect_to owner_restaurant_wine_lists_path(@restaurant)
    end

    private

    def set_restaurant
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
    end

    def set_wine_list
      @wine_list = @restaurant.wine_lists.find(params[:id])
    end

    def wine_list_params
      params.require(:wine_list).permit(:name, :season, :position, :active)
    end
  end
end
