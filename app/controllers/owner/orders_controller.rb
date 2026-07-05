module Owner
  class OrdersController < BaseController
    before_action :set_restaurant
    before_action :set_order, only: %i[show approve cancel]

    def index
      @orders = @restaurant.orders.includes(:customer, :restaurant_table, order_items: :wine).recent
      @orders = @orders.where(status: params[:status]) if params[:status].present?
    end

    def show
    end

    def approve
      @order.approve!
      redirect_to owner_restaurant_orders_path(@restaurant), notice: t("owner.orders.approved"), status: :see_other
    end

    def cancel
      @order.cancel!
      redirect_to owner_restaurant_orders_path(@restaurant), notice: t("owner.orders.cancelled"), status: :see_other
    end

    private

    def set_restaurant
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
    end

    def set_order
      @order = @restaurant.orders.find(params[:id])
    end
  end
end
