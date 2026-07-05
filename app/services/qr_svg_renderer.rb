# Renders a URL as an SVG QR code that inherits its container's text color.
class QrSvgRenderer
  def self.call(url)
    qrcode = RQRCode::QRCode.new(url)
    # rqrcode only treats a color as a literal CSS keyword when it is a
    # Symbol; String values get a "#" prefixed (e.g. "currentColor" =>
    # "#currentColor"), which is invalid and renders nothing. Passing
    # :currentColor lets the QR inherit the container's text color, and
    # omitting :fill leaves the background transparent.
    # The SVG is generated entirely by rqrcode from a URL we build ourselves,
    # so it is safe to render unescaped.
    qrcode.as_svg(
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true,
      use_path: true,
      color: :currentColor
    ).html_safe
  end
end
