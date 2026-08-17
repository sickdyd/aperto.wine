# Public, unauthenticated cart endpoints. One Cart instance is built per
# request and reused across every action — Cart memoizes its reads, so two
# instances for the same restaurant in one request would not see each
# other's writes (see Cart#items).
class CartsController < ApplicationController
  include CustomerScoped

  before_action :set_restaurant
  before_action :set_cart

  def show
    @table = current_table
  end

  # Redirects back to the menu on success — the diner almost always came
  # from there and is likely adding more than one wine, so returning to the
  # cart page after every single add cost up to four page loads to build a
  # two-item order. The sticky cart bar (menus/_cart_bar) picks up the new
  # total immediately, and stays the way back to the cart page. A failure
  # redirects to the cart page instead, where the error has full context —
  # see #flash_error.
  def add_item
    result = @cart.add(wine_id: integer_param(:wine_id), serving: serving_param,
                        glass_size_ml: integer_param(:glass_size_ml),
                        quantity: integer_param(:quantity) || 1)
    if result.success?
      redirect_to menu_path_for(@restaurant), notice: t("cart.item_added")
    else
      flash_error(result)
      redirect_to cart_path(restaurant_slug: @restaurant.slug)
    end
  end

  def update_item
    result = @cart.update_quantity(wine_id: integer_param(:wine_id), serving: serving_param,
                                    glass_size_ml: integer_param(:glass_size_ml),
                                    quantity: integer_param(:quantity) || 0)
    flash_error(result)
    redirect_to cart_path(restaurant_slug: @restaurant.slug)
  end

  def remove_item
    @cart.remove(wine_id: integer_param(:wine_id), serving: serving_param,
                 glass_size_ml: integer_param(:glass_size_ml))
    redirect_to cart_path(restaurant_slug: @restaurant.slug)
  end

  def destroy
    @cart.clear
    redirect_to cart_path(restaurant_slug: @restaurant.slug)
  end

  private

  # Missing/blank/non-numeric params must never reach the database as a raw
  # string (Postgres would raise a type-cast error on an integer column,
  # turning a bad param into a 500) — coerce here, once, and let a nil
  # through so Cart's own validation produces a clean Result failure.
  def integer_param(key)
    Integer(params[key], 10, exception: false)
  end

  # A "serving" key entirely absent from the request is the signature of
  # stale HTML: a menu page rendered and cached in a diner's browser before
  # this deploy, whose add-to-cart form never had a serving field to send.
  # Diners keep a restaurant's menu tab open across a whole meal, so a
  # mid-service deploy would otherwise break every already-open tab's add
  # button until the diner manually reloads, with no indication why. Reading
  # the absent key as "glass" preserves the pre-serving glass-only contract
  # for exactly that stale request, without weakening validation for any
  # other client: a request that *does* send the key — blank or bogus — is
  # passed straight through to Cart unvalidated and still fails closed as
  # :invalid_serving there, the same as before. This mirrors how a legacy
  # session line with no "serving" key is read as a glass (see Cart's
  # normalized_serving) — the same fallback, applied one layer further out,
  # to the request instead of the stored line.
  def serving_param
    params.key?(:serving) ? params[:serving] : "glass"
  end

  def flash_error(result)
    return if result.success?

    flash[:alert] = t("cart.errors.#{result.error}")
  end
end
