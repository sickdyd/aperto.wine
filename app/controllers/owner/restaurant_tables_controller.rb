module Owner
  class RestaurantTablesController < BaseController
    before_action :set_restaurant
    before_action :set_table, only: %i[edit update destroy qr]

    def index
      @grouped_tables = @restaurant.restaurant_tables.grouped_by_area
    end

    def new
      @table = @restaurant.restaurant_tables.build(active: true)
    end

    def create
      @table = @restaurant.restaurant_tables.build(table_params)

      if @table.save
        redirect_to owner_restaurant_tables_path(@restaurant), notice: t("owner.tables.created"), status: :see_other
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @table.update(table_params)
        redirect_to owner_restaurant_tables_path(@restaurant), notice: t("owner.tables.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @table.destroy!
      redirect_to owner_restaurant_tables_path(@restaurant), notice: t("owner.tables.deleted"), status: :see_other
    end

    def qr
      @menu_url = table_menu_url(@table.token)
      @qr_svg = QrSvgRenderer.call(@menu_url)
    end

    def bulk_print
      tables = @restaurant.restaurant_tables.active
      tables = tables.where(area: params[:area]) if params[:area].present?
      @grouped_tables = tables.grouped_by_area
      @table_qr_svgs = @grouped_tables.values.flatten.index_with do |table|
        QrSvgRenderer.call(table_menu_url(table.token))
      end
    end

    def bulk_new
      @generation = TableBulkGeneration.new(restaurant: @restaurant, floor_label: t("owner.tables.bulk.floor_default"))
    end

    def bulk_create
      @generation = TableBulkGeneration.new(restaurant: @restaurant, **bulk_params.to_h.symbolize_keys)

      if @generation.save
        redirect_to owner_restaurant_tables_path(@restaurant), notice: bulk_notice(@generation), status: :see_other
      else
        render :bulk_new, status: :unprocessable_entity
      end
    end

    def destroy_all
      count = @restaurant.restaurant_tables.destroy_all.size
      redirect_to owner_restaurant_tables_path(@restaurant), notice: t("owner.tables.bulk.deleted_all", count: count), status: :see_other
    end

    private

    def set_restaurant
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
    end

    def set_table
      @table = @restaurant.restaurant_tables.find(params[:id])
    end

    def table_params
      params.require(:restaurant_table).permit(:name, :area, :position, :active)
    end

    def bulk_params
      params.require(:table_bulk_generation).permit(:floors_count, :tables_per_floor, :floor_label, :name_pattern)
    end

    def bulk_notice(generation)
      if generation.skipped_count.positive?
        t("owner.tables.bulk.created_with_skipped", created: generation.created_count, skipped: generation.skipped_count)
      else
        t("owner.tables.bulk.created", created: generation.created_count)
      end
    end
  end
end
