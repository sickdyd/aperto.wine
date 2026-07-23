require "test_helper"

class WinesHelperTest < ActionView::TestCase
  Wine.colors.each_key do |color|
    test "wine_color_dot renders a #{color} dot with a screen-reader label" do
      label = I18n.t("owner.wines.colors.#{color}")
      expected = %(<span class="wine-dot wine-dot-#{color}" aria-hidden="true"></span>) +
                 %(<span class="sr-only">#{label}</span>)

      assert_dom_equal expected, wine_color_dot(color)
    end
  end

  test "wine_color_dot omits the screen-reader label when label: false" do
    assert_dom_equal %(<span class="wine-dot wine-dot-red" aria-hidden="true"></span>),
      wine_color_dot("red", label: false)
  end

  test "wine_color_dot falls back to red for an unknown color" do
    html = wine_color_dot("vermouth\" onmouseover=\"alert(1)", label: false)

    assert_dom_equal %(<span class="wine-dot wine-dot-red" aria-hidden="true"></span>), html
  end

  test "wine_color_dot falls back to red for a nil color" do
    assert_dom_equal %(<span class="wine-dot wine-dot-red" aria-hidden="true"></span>),
      wine_color_dot(nil, label: false)
  end
end
