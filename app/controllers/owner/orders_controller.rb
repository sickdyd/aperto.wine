module Owner
  class OrdersController < BaseController
    # Names the window the browser is holding, so the next poll can say "these
    # I already told you about" without the server keeping any per-tab state.
    ORDER_WINDOW_HEADER = "X-Order-Window".freeze

    before_action :set_restaurant
    before_action :set_order, only: %i[show approve cancel]

    # #notifications is the one action here a page calls on a timer, so it is
    # the one that can be leaned on. The ceiling clears several tabs polling at
    # the client's cadence many times over while still bounding a session that
    # decides to hammer it; it is keyed on the signed-in owner, which every
    # request that gets this far already has.
    rate_limit to: 120, within: 1.minute, only: :notifications,
               by: -> { current_user.id }, with: -> { head :too_many_requests }

    def index
      @orders = @restaurant.orders.includes(:customer, :restaurant_table, order_items: :wine).recent
      @orders = @orders.where(status: params[:status]) if params[:status].present?
    end

    def show
    end

    # What an open owner page asks for on a timer: the orders that have arrived
    # since it last looked, and the pending tally for the sidebar badge.
    #
    # The browser holds the state, not the server: it sends back the window it
    # was last given (`known`) and the tally it is currently showing (`count`),
    # both untrusted and both used for nothing but comparison. When neither has
    # moved there is nothing to say, and saying nothing is cheaper than saying
    # so in markup — hence the 204 rather than an empty stream.
    def notifications
      window = @restaurant.orders.notification_window.includes(:restaurant_table).to_a
      @pending_count = @restaurant.orders.pending.count
      @new_orders = window.reject { |order| known_order_ids.include?(order.id) }

      response.set_header(ORDER_WINDOW_HEADER, window.map(&:id).join(","))

      if @new_orders.empty? && known_pending_count == @pending_count
        head :no_content
      else
        render :notifications, formats: :turbo_stream
      end
    end

    # Both transitions can legitimately do nothing: the order moved between
    # the board being rendered and the button being pressed (another tab, a
    # second member of staff, a Turbo retry), and Order#approve!/#cancel!
    # answer false rather than transitioning it twice. Flashing success
    # regardless would hide exactly the state confusion those guards exist to
    # prevent — the owner would read "approved" and be looking at a cancelled
    # order.
    def approve
      if @order.approve!
        redirect_to owner_restaurant_orders_path(@restaurant), notice: t("owner.orders.approved"), status: :see_other
      else
        redirect_to owner_restaurant_orders_path(@restaurant), alert: t("owner.orders.approve_failed"), status: :see_other
      end
    end

    def cancel
      if @order.cancel!
        redirect_to owner_restaurant_orders_path(@restaurant), notice: t("owner.orders.cancelled"), status: :see_other
      else
        redirect_to owner_restaurant_orders_path(@restaurant), alert: t("owner.orders.cancel_failed"), status: :see_other
      end
    end

    private

    def set_restaurant
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
    end

    def set_order
      @order = @restaurant.orders.find(params[:id])
    end

    # The ids the browser says it has already announced. Anything that is not a
    # list of integers is treated as no ids at all rather than as an error: a
    # poller cannot show the owner a 400, and the worst a junk value can do is
    # repeat one announcement. The slice is what keeps a crafted request from
    # handing the reject below an unbounded list to walk.
    def known_order_ids
      raw = params[:known]
      return [] unless raw.is_a?(Array)

      raw.first(Order::NOTIFICATION_WINDOW).filter_map { |value| Integer(value.to_s, exception: false) }
    end

    # nil — absent or unparseable — never equals a count, so a browser that
    # cannot say what it is showing gets the badge restated.
    def known_pending_count
      Integer(params[:count].to_s, exception: false)
    end
  end
end
