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
      # rqrcode only treats a color as a literal CSS keyword when it is a
      # Symbol; String values get a "#" prefixed (e.g. "currentColor" =>
      # "#currentColor"), which is invalid and renders nothing. Passing
      # :currentColor lets the QR inherit the container's text color, and
      # omitting :fill leaves the background transparent.
      qrcode.as_svg(
        shape_rendering: "crispEdges",
        module_size: 4,
        standalone: true,
        use_path: true,
        color: :currentColor
      )
    end
  end
end
