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
  # route never carries) does not apply here. set_restaurant is opt-in per
  # action (see CustomerScoped), so #show simply never declares it rather
  # than declaring it for every action and skipping it back off.
  before_action :set_restaurant, only: [ :create, :index ]
  before_action :set_order_history, only: [ :create, :index ]
  before_action :set_cart, only: :create

  # IP-scoped ceiling: comfortably clears a large table of diners (roughly
  # 15-20 people) sharing one restaurant's NAT'd wifi, each placing at most
  # a couple of orders over the course of a sitting, while still bounding a
  # script that rotates cookie jars per request. 8x the per-session ceiling
  # keeps it well above legitimate shared-IP traffic without being
  # effectively unlimited.
  IP_RATE_LIMIT = 40

  # Two independent limiters, since a fresh cookie jar defeats a
  # session-only key on its own (see the by: comment below).
  #
  # Session-scoped: catches an honest diner double-tapping submit. Keyed on
  # the session id, falling back to the remote IP, mirroring
  # Owner::AddressSuggestionsController's by:-keyed usage. session.id is nil
  # until the session has actually been written, which a fresh visitor's
  # first-ever request cannot guarantee — a bare session.id.to_s key would
  # collapse every such visitor onto the same blank-string bucket.
  rate_limit to: 5, within: 1.minute, only: :create,
             by: -> { session.id.to_s.presence || request.remote_ip },
             with: -> { redirect_to cart_path(restaurant_slug: @restaurant.slug), alert: t("orders.errors.rate_limited") }

  # IP-scoped: closes the bypass above. Placing an order always requires a
  # session-backed cart (see #set_cart / Cart), so by the time #create runs
  # session.id is *always* present — and it is a fresh random id for every
  # fresh cookie jar, so the session-scoped limiter above never actually
  # falls back to request.remote_ip on this action. Keying a second,
  # higher-ceiling limiter purely on remote_ip cannot be evaded that way.
  # On trip we redirect with a translated flash rather than a bare 429: a
  # diner may legitimately retry a few seconds later.
  rate_limit to: IP_RATE_LIMIT, within: 1.minute, only: :create, name: "orders_ip",
             by: -> { request.remote_ip },
             with: -> { redirect_to cart_path(restaurant_slug: @restaurant.slug), alert: t("orders.errors.rate_limited") }

  def create
    return honeypot_response if honeypot_tripped?

    result = PlaceOrder.call(
      cart: @cart, restaurant: @restaurant, table: current_table,
      customer: current_user, guest_name: order_params[:guest_name].presence
    )

    if result.success?
      # Recorded on success only, before the redirect — this is the sole
      # place an order enters the device's history. #show deliberately
      # never calls #record (see its comment below): recording happens at
      # placement, not at every later view of the token.
      @order_history.record(result.order)
      redirect_to order_status_path(public_token: result.order.public_token)
    else
      redirect_to cart_path(restaurant_slug: @restaurant.slug), alert: t("orders.errors.#{result.error}")
    end
  end

  # The device's own "your orders" list for this restaurant — resolved
  # entirely from the signed cookie, no session or account involved. Reads
  # never rewrite the cookie (see OrderHistory#orders), so repeat visits are
  # side-effect free and, unlike #create, carry no rate limit.
  def index
    @orders = @order_history.orders
  end

  # Public capability lookup: the public_token is the only key. Never falls
  # back to an id or to "the current user's most recent order" — either
  # would let one diner read another's order. Restaurant.active mirrors
  # every other customer path (menu, cart): an order that belongs to a
  # restaurant the owner has since deactivated 404s rather than staying
  # reachable — the token is still the capability, but consistency with the
  # rest of the public surface wins.
  #
  # Deliberately does not call @order_history.record(@order): someone
  # opening a status link a diner handed them (or their own link from a
  # different device) must not silently get that order added to this
  # device's list. Only #create records — see the comment there.
  def show
    @order = Order.joins(:restaurant).merge(Restaurant.active).find_by!(public_token: params[:public_token])
    @order_history = OrderHistory.new(cookies: cookies, restaurant: @order.restaurant)
  end

  private

  # guest_name is the only diner-supplied string that is persisted (already
  # length-capped on the model). status, total_amount_cents, restaurant_id,
  # restaurant_table_id, customer_id and public_token are all set
  # server-side in PlaceOrder and never accepted from params.
  def order_params
    params.permit(:guest_name)
  end

  # Read from the raw params, not the permitted order_params: Strong
  # Parameters' #permit silently drops non-scalar values, so a submission
  # like contact_reference[]=x would come back nil through
  # order_params[:contact_reference] and never trip the honeypot at all.
  # Any present value here — a string, an array, or a nested hash — means
  # the field was touched by something that isn't a human, so all of them
  # count as a trip.
  def honeypot_tripped?
    params[:contact_reference].present?
  end

  # A bot that fills the honeypot creates no order and is redirected to the
  # menu with no flash — a real success lands on the order's own status
  # page instead, so the two responses are trivially distinguishable to
  # anything that inspects them. There is no attempt to hide that; the
  # honeypot only withholds anything actionable (an order, a token, a
  # success message) from an automated submission.
  def honeypot_response
    redirect_to menu_path_for(@restaurant)
  end
end
