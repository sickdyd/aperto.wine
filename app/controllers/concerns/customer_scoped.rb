# Shared restaurant/table resolution for public, unauthenticated customer
# endpoints (the menu, the cart, and — in a later task — order placement).
#
# A diner reaches these endpoints two ways:
#   - the generic restaurant QR / link: /menu/:id, /menu/:restaurant_id/cart
#   - a per-table QR: /t/:table_token
#
# Either way we resolve @restaurant. When arriving via a table token whose
# table is still active, we also remember it in the session so that later
# requests for the same restaurant — even ones that only carry a restaurant
# id, like the cart — can still be attributed to that table.
#
# set_restaurant is opt-in per action, not applied automatically to every
# action of an including controller — most controllers want it everywhere
# (`before_action :set_restaurant`), but OrdersController#show looks a
# customer's order up solely by public_token and never needs a restaurant,
# so it simply never declares the before_action for that action rather than
# declaring it for everything and then un-declaring it with
# skip_before_action.
module CustomerScoped
  extend ActiveSupport::Concern

  private

  # An inactive restaurant must 404 rather than becoming reachable, however
  # it's addressed — hence Restaurant.active rather than Restaurant.find.
  #
  # When resolving via a table QR, @restaurant_table is set directly from
  # *this* request's own token — only when that table is still active —
  # mirroring MenusController's original single-method resolver exactly. It
  # deliberately does not fall back to current_table's session-wide lookup:
  # a retired or replaced token must never surface a *different* table left
  # over in the session from an earlier scan this browser session.
  def set_restaurant
    if params[:table_token].present?
      table = RestaurantTable.find_by!(token: params[:table_token])
      @restaurant = Restaurant.active.find(table.restaurant_id)
      if table.active?
        @restaurant_table = table
        remember_table(table)
      end
    else
      @restaurant = Restaurant.active.find(params[:restaurant_id] || params[:id])
    end
  end

  # One Cart per request (it memoizes its reads — see Cart#items) shared by
  # every controller that needs it, so two instances for the same
  # restaurant in one request never see each other's writes.
  def set_cart
    @cart = Cart.new(session: session, restaurant: @restaurant)
  end

  # One OrderHistory per request (it memoizes #orders — see OrderHistory),
  # shared by every controller that needs it. Depends on @restaurant, so
  # like set_cart it is opt-in per action, declared only where a restaurant
  # has already been resolved.
  def set_order_history
    @order_history = OrderHistory.new(cookies: cookies, restaurant: @restaurant)
  end

  # The table this session has attached to @restaurant, if any — used by the
  # cart (and, in a later task, order placement) so a request carrying only
  # a restaurant id can still be attributed to a table remembered from an
  # earlier /t/:table_token visit. nil unless a table QR was scanned for
  # this restaurant *and* that table is still active *and* still belongs to
  # this restaurant — a retired or reassigned token must resolve to no
  # table, never a stale one.
  def current_table
    token = (session[:table_tokens] || {})[@restaurant.id.to_s]
    return nil if token.blank?

    table = RestaurantTable.find_by(token: token)
    table if table&.active? && table.restaurant_id == @restaurant.id
  end

  def remember_table(table)
    tokens = session[:table_tokens] || {}
    session[:table_tokens] = tokens.merge(table.restaurant_id.to_s => table.token)
  end
end
