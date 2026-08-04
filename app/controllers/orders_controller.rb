# Public, unauthenticated order placement and status lookup. #create is the
# feature's only public write endpoint, so it carries the abuse controls: a
# rate limit and a honeypot. A signed-in diner may also place an order —
# current_user becomes the order's customer when present, nil otherwise —
# but authentication is never required.
class OrdersController < ApplicationController
  include CustomerScoped

  # #show looks a customer's order up solely by public_token and never by
  # restaurant — the token itself is the capability, so CustomerScoped's
  # restaurant resolution (which needs a restaurant_id/id/table_token this
  # route never carries) does not apply here.
  skip_before_action :set_restaurant, only: :show

  before_action :set_cart, only: :create

  # Keyed on the session id, falling back to the remote IP, mirroring
  # Owner::AddressSuggestionsController's by:-keyed usage. session.id is nil
  # until the session has actually been written, which a fresh visitor's
  # first-ever request cannot guarantee — a bare session.id.to_s key would
  # collapse every such visitor onto the same blank-string bucket. On trip
  # we redirect with a translated flash rather than a bare 429: a diner may
  # legitimately retry a few seconds later.
  rate_limit to: 5, within: 1.minute, only: :create,
             by: -> { session.id.to_s.presence || request.remote_ip },
             with: -> { redirect_to cart_path(restaurant_id: @restaurant), alert: t("orders.errors.rate_limited") }

  def create
    return honeypot_response if order_params[:website].present?

    result = PlaceOrder.call(
      cart: @cart, restaurant: @restaurant, table: current_table,
      customer: current_user, guest_name: order_params[:guest_name].presence
    )

    if result.success?
      redirect_to order_status_path(public_token: result.order.public_token)
    else
      redirect_to cart_path(restaurant_id: @restaurant), alert: t("orders.errors.#{result.error}")
    end
  end

  # Public capability lookup: the public_token is the only key. Never falls
  # back to an id or to "the current user's most recent order" — either
  # would let one diner read another's order.
  def show
    @order = Order.find_by!(public_token: params[:public_token])
  end

  private

  def set_cart
    @cart = Cart.new(session: session, restaurant: @restaurant)
  end

  # guest_name is the only diner-supplied string that is persisted (already
  # length-capped on the model). status, total_amount_cents, restaurant_id,
  # restaurant_table_id, customer_id and public_token are all set
  # server-side in PlaceOrder and never accepted from params.
  def order_params
    params.permit(:guest_name, :website)
  end

  # A bot that fills the honeypot gets no signal that it was caught: no
  # order is created, but the response looks as much like the success a
  # human diner would see as is practical without fabricating an order.
  def honeypot_response
    redirect_to menu_path(id: @restaurant), notice: t("orders.placed")
  end
end
