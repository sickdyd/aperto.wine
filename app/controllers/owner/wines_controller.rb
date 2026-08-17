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
        redirect_to owner_restaurant_wines_path(@restaurant), notice: t("owner.wines.created"), status: :see_other
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    # available_glasses is a live reservation counter now — diners spend it
    # while this form sits open — but the form still edits it as an absolute
    # number seeded when the page was rendered. Saving an unrelated change
    # would otherwise write that stale number back and resurrect glasses
    # already reserved. lock_version (a hidden field, see wines/_form) turns
    # that into a StaleObjectError, and the owner is shown the wine as it
    # actually stands rather than having their stale copy silently win.
    #
    # The reload is deliberate: their unsaved edits are discarded along with
    # the stale numbers they were sitting next to, because there is no way to
    # tell which of the two an owner meant to keep. 409 rather than 422 —
    # nothing they typed was invalid, the record simply moved.
    def update
      if @wine.update(wine_params)
        redirect_to owner_restaurant_wines_path(@restaurant), notice: t("owner.wines.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::StaleObjectError
      @wine.reload
      flash.now[:alert] = t("owner.wines.stale_update", glasses: @wine.available_glasses)
      render :edit, status: :conflict
    end

    def destroy
      @wine.destroy!
      redirect_to owner_restaurant_wines_path(@restaurant), notice: t("owner.wines.deleted"), status: :see_other
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
        :available_glasses, :position, :active,
        :abv, :style, :short_description,
        :body, :tannins, :acidity, :sweetness,
        :organic, :natural_wine, :vegan, :biodynamic,
        # The _list writers split/join a comma-separated string onto the
        # array columns — the arrays themselves (:aromas, :food_pairings)
        # are deliberately never permitted here (see Wine#aromas_list=).
        :aromas_list, :food_pairings_list,
        # Rails compares this against the stored column and raises
        # StaleObjectError when they disagree; it is never written from it.
        :lock_version
      )
    end
  end
end
