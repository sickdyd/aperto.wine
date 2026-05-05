module Owner
  class QrCodesController < BaseController
    def show
      @restaurant = current_user.restaurants.find(params[:restaurant_id])
      @menu_url = menu_url(@restaurant)
      @qr_svg = generate_qr_svg(@menu_url)
    end

    private

    def generate_qr_svg(url)
      qrcode = RQRCode::QRCode.new(url)
      qrcode.as_svg(
        shape_rendering: "crispEdges",
        module_size: 4,
        standalone: true,
        use_path: true,
        color: "currentColor",
        fill: "none"
      )
    end
  end
end
