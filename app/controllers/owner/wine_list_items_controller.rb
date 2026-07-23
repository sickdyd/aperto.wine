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
        respond_with_members(notice: t("owner.wine_lists.members.added"))
      else
        respond_with_members(alert: t("owner.wine_lists.members.already_added"))
      end
    rescue ActiveRecord::RecordNotUnique
      # The unique index can still fire under concurrent adds even though the
      # model validation passed at build time.
      respond_with_members(alert: t("owner.wine_lists.members.already_added"))
    end

    def update
      if @wine_list_item.update(wine_list_item_params)
        respond_with_members(notice: t("owner.wine_lists.members.reordered"))
      else
        respond_with_members(alert: @wine_list_item.errors.full_messages.to_sentence)
      end
    end

    def destroy
      @wine_list_item.destroy!
      respond_with_members(notice: t("owner.wine_lists.members.removed"))
    end

    # Bulk reorder: persists the full submitted order in one transaction so
    # drag-and-drop reordering doesn't require one request per moved row.
    def sort
      item_ids = Array(params[:item_ids]).reject(&:blank?)
      return head :unprocessable_entity if item_ids.empty?

      items = item_ids.map { |id| @wine_list.wine_list_items.find(id) }

      WineListItem.transaction do
        items.each_with_index { |item, index| item.update!(position: index + 1) }
      end

      respond_to do |format|
        format.turbo_stream { head :ok }
        format.html { redirect_to edit_path, notice: t("owner.wine_lists.members.reordered"), status: :see_other }
      end
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

    # Shared response for create/update/destroy: a turbo_stream re-render of
    # the members container for JS clients, with an html redirect fallback
    # (and matching flash) for no-JS requests.
    def respond_with_members(notice: nil, alert: nil)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = notice if notice
          flash.now[:alert] = alert if alert
          render turbo_stream: [
            turbo_stream.replace(
              "wine_list_members",
              partial: "owner/wine_lists/members",
              locals: { wine_list: @wine_list }
            ),
            turbo_stream.replace("flash-messages", partial: "owner/shared/flash")
          ]
        end
        format.html { redirect_to edit_path, notice: notice, alert: alert, status: :see_other }
      end
    end
  end
end
