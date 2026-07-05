module Owner
  class QrCodesController < BaseController
    def show
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
      @menu_url = menu_url(@restaurant)
      @qr_svg = QrSvgRenderer.call(@menu_url)
    end
  end
end
