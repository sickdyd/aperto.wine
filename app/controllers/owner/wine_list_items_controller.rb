module Owner
  class WineListItemsController < BaseController
    before_action :set_restaurant
    before_action :set_wine_list
    before_action :set_wine_list_item, only: %i[update destroy]

    def create
      # Scope the wine to the restaurant so a wine from another restaurant 404s
      # before it can reach the model-level same-restaurant validation.
      wine = @restaurant.wines.find(params[:wine_id])
      item = @wine_list.wine_list_items.build(wine: wine)

      if item.save
        redirect_to edit_path, notice: t("owner.wine_lists.members.added")
      else
        redirect_to edit_path, alert: t("owner.wine_lists.members.already_added")
      end
    rescue ActiveRecord::RecordNotUnique
      # The unique index can still fire under concurrent adds even though the
      # model validation passed at build time.
      redirect_to edit_path, alert: t("owner.wine_lists.members.already_added")
    end

    def update
      if @wine_list_item.update(wine_list_item_params)
        redirect_to edit_path, notice: t("owner.wine_lists.members.reordered")
      else
        redirect_to edit_path, alert: @wine_list_item.errors.full_messages.to_sentence
      end
    end

    def destroy
      @wine_list_item.destroy!
      redirect_to edit_path, notice: t("owner.wine_lists.members.removed")
    end

    private

    def set_restaurant
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
    end

    def set_wine_list
      @wine_list = @restaurant.wine_lists.find(params[:wine_list_id])
    end

    def set_wine_list_item
      @wine_list_item = @wine_list.wine_list_items.find(params[:id])
    end

    def edit_path
      edit_owner_restaurant_wine_list_path(@restaurant, @wine_list)
    end

    def wine_list_item_params
      params.require(:wine_list_item).permit(:position)
    end
  end
end
