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

    # Adds every one of the restaurant's wines that isn't already on the list,
    # appended after the existing items in `Wine.by_position` order. This is the
    # replacement for the old synthetic "All Wines" list: an owner who wants the
    # whole cellar on the menu makes one list and presses this once.
    #
    # `insert_all` with `unique_by` gives one round trip and an ON CONFLICT DO
    # NOTHING, so a double submit (or a concurrent add of the same wine) is a
    # no-op rather than a duplicate or a 500. Bypassing per-row validations is
    # safe for the same reason it is in #sort: both sides are already scoped to
    # @restaurant, so the same-restaurant invariant can't be violated, and the
    # unique index enforces per-list wine uniqueness.
    def create_all
      wines = @restaurant.wines
                         .by_position
                         .where.not(id: @wine_list.wine_list_items.select(:wine_id))

      return respond_with_members(alert: t("owner.wine_lists.members.all_added")) if wines.empty?

      next_position = (@wine_list.wine_list_items.maximum(:position) || 0) + 1
      now = Time.current
      rows = wines.each_with_index.map do |wine, index|
        {
          wine_list_id: @wine_list.id,
          wine_id: wine.id,
          position: next_position + index,
          created_at: now,
          updated_at: now
        }
      end

      added = WineListItem.insert_all(rows, unique_by: %i[wine_list_id wine_id]).count

      respond_with_members(notice: t("owner.wine_lists.members.added_all", count: added))
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
    #
    # A single bulk `update_all` (one UPDATE ... CASE, one round trip) replaces
    # what used to be a per-id `find` plus a per-row `update!` (up to 3N
    # queries, with row locks held across N round trips and a deadlock window
    # between concurrent sorts of the same list). Skipping per-row validations
    # here is deliberate and safe: this only ever rewrites `position` on rows
    # already scoped to `@wine_list`, so it can't violate the same-restaurant
    # or per-list wine-uniqueness invariants — those are enforced at create
    # time (see WineListItem#wine_and_list_share_restaurant and the unique
    # index on [wine_list_id, wine_id]).
    def sort
      # Permit only an array of scalars: a hash-shaped or otherwise malformed
      # payload (e.g. item_ids[0][x]=y) is dropped entirely instead of
      # reaching `find` as an ActionController::Parameters object.
      item_ids = Array(params.permit(item_ids: [])[:item_ids]).reject(&:blank?).uniq
      return head :unprocessable_entity if item_ids.empty?

      items = @wine_list.wine_list_items.where(id: item_ids)
      raise ActiveRecord::RecordNotFound if items.size != item_ids.size

      WineListItem.transaction do
        when_clauses = item_ids.map { "WHEN id = ? THEN ?" }.join(" ")
        bindings = item_ids.each_with_index.flat_map { |id, index| [ id, index + 1 ] }
        case_sql = WineListItem.sanitize_sql_array(
          [ "CASE #{when_clauses} END", *bindings ]
        )
        items.update_all("position = #{case_sql}")
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
