# Public, unauthenticated cart endpoints. One Cart instance is built per
# request and reused across every action — Cart memoizes its reads, so two
# instances for the same restaurant in one request would not see each
# other's writes (see Cart#items).
class CartsController < ApplicationController
  include CustomerScoped

  before_action :set_cart

  def show
    @table = current_table
  end

  def add_item
    result = @cart.add(wine_id: integer_param(:wine_id), glass_size_ml: integer_param(:glass_size_ml),
                        quantity: integer_param(:quantity) || 1)
    flash_error(result)
    redirect_to cart_path(restaurant_id: @restaurant)
  end

  def update_item
    result = @cart.update_quantity(wine_id: integer_param(:wine_id), glass_size_ml: integer_param(:glass_size_ml),
                                    quantity: integer_param(:quantity) || 0)
    flash_error(result)
    redirect_to cart_path(restaurant_id: @restaurant)
  end

  def remove_item
    @cart.remove(wine_id: integer_param(:wine_id), glass_size_ml: integer_param(:glass_size_ml))
    redirect_to cart_path(restaurant_id: @restaurant)
  end

  def destroy
    @cart.clear
    redirect_to cart_path(restaurant_id: @restaurant)
  end

  private

  def set_cart
    @cart = Cart.new(session: session, restaurant: @restaurant)
  end

  # Missing/blank/non-numeric params must never reach the database as a raw
  # string (Postgres would raise a type-cast error on an integer column,
  # turning a bad param into a 500) — coerce here, once, and let a nil
  # through so Cart's own validation produces a clean Result failure.
  def integer_param(key)
    Integer(params[key], 10, exception: false)
  end

  def flash_error(result)
    return if result.success?

    flash[:alert] = t("cart.errors.#{result.error}")
  end
end
