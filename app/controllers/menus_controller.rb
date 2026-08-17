class MenusController < ApplicationController
  include CustomerScoped

  before_action :set_restaurant, only: :show
  before_action :set_published_wine_list, only: :show
  before_action :redirect_to_canonical_url, only: :show
  # Depends on @restaurant, so it comes after set_restaurant. Building an
  # OrderHistory does no query on its own (#any?/#orders only hit the
  # database once the cookie actually has tokens for this restaurant — see
  # OrderHistory), so a first-time visitor with no order_tokens cookie
  # costs the menu, the hottest page in the app, nothing extra.
  # only: :show, like set_cart below it — CustomerScoped's callbacks are
  # opt-in per action, and a blanket declaration here would quietly stop
  # being true the moment this controller grows a second action.
  before_action :set_order_history, only: :show
  before_action :set_cart, only: :show

  # The published menu, reached three ways: its canonical slug URL, the
  # restaurant slug on its own, or a table QR. @restaurant_table is set by
  # CustomerScoped's set_restaurant directly from this request's own table
  # token, if any — see that method for why it does not use current_table.
  def show
    # A collection of one: the view and MenusHelper both take a list of
    # lists, and keeping that shape means neither had to learn about
    # publishing. Availability is driven by the wines/bottles, never by list
    # membership. Nil when nothing is published — the view falls through to
    # its empty state rather than 404ing a QR code someone just scanned.
    @wine_lists = Array(@wine_list)
    # @cart is set by set_cart above — reused by the view to decide whether
    # the sticky cart bar renders and what it shows.
  end

  # /menu/:id — the pre-slug URL, still live on printed QR codes.
  def legacy
    restaurant = Restaurant.active.find(params[:id])
    redirect_to restaurant_menu_path(restaurant_slug: restaurant.slug), status: :found
  end

  private

  def set_published_wine_list
    @wine_list = @restaurant.wine_lists.published
                            .includes(wine_list_items: { wine: :wine_bottles })
                            .first
  end

  # Funnels every way of addressing this restaurant onto the published list's
  # own URL: the bare restaurant slug, and any draft list's slug.
  #
  # Always 302, never 301: the target changes whenever the owner publishes a
  # different list, and a permanent redirect cached in a diner's browser
  # would pin them to the retired menu — the exact failure the stable
  # restaurant-level QR exists to prevent.
  def redirect_to_canonical_url
    return if params[:table_token].present?

    requested = params[:wine_list_slug]

    # A slug belonging to no list of this restaurant is a wrong URL, not a
    # retired menu — 404 rather than quietly landing them somewhere else.
    raise ActiveRecord::RecordNotFound if requested.present? && !@restaurant.wine_lists.exists?(slug: requested)

    # Covers all four cases at once, including the one that would otherwise
    # loop: nothing published and no list requested is nil == nil, so the bare
    # restaurant URL renders its empty state instead of redirecting to itself.
    return if requested == @wine_list&.slug

    redirect_to canonical_menu_path, status: :found
  end

  def canonical_menu_path
    if @wine_list
      wine_list_menu_path(restaurant_slug: @restaurant.slug, wine_list_slug: @wine_list.slug)
    else
      restaurant_menu_path(restaurant_slug: @restaurant.slug)
    end
  end
end
