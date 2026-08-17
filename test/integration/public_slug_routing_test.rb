require "test_helper"

# The public menu ends config/routes.rb with ":restaurant_slug", a route that
# matches any single path segment. Nothing but declaration order stops it
# swallowing the auth pages, the cart, or the whole owner namespace, and that
# order is easy to break by adding a route in the "obvious" place. These tests
# fail loudly if it ever does.
class PublicSlugRoutingTest < ActionDispatch::IntegrationTest
  RESERVED_PATHS = {
    "/up" => { controller: "rails/health", action: "show" },
    "/en/sign_in" => { controller: "sessions", action: "new", locale: "en" },
    "/en/sign_up" => { controller: "registrations", action: "new", locale: "en" },
    "/en/privacy" => { controller: "legal", action: "privacy", locale: "en" },
    "/en/terms" => { controller: "legal", action: "terms", locale: "en" },
    "/en/owner/restaurants" => { controller: "owner/restaurants", action: "index", locale: "en" },
    "/en/menu/1" => { controller: "menus", action: "legacy", locale: "en", id: "1" },
    "/en/t/some-token" => { controller: "menus", action: "show", locale: "en", table_token: "some-token" },
    "/en/orders/some-token" => { controller: "orders", action: "show", locale: "en", public_token: "some-token" },
    "/en" => { controller: "home", action: "index", locale: "en" },
    "/it" => { controller: "home", action: "index", locale: "it" },
    "/" => { controller: "home", action: "index" }
  }.freeze

  RESERVED_PATHS.each do |path, expected|
    test "#{path} is not swallowed by the restaurant slug route" do
      assert_equal expected, Rails.application.routes.recognize_path(path)
    end
  end

  test "the cart keeps its own prefix rather than nesting under the restaurant slug" do
    assert_equal(
      { controller: "carts", action: "show", locale: "en", restaurant_slug: "osteria-del-borgo" },
      Rails.application.routes.recognize_path("/en/cart/osteria-del-borgo")
    )
  end

  test "Active Storage routes still resolve" do
    assert_equal(
      { controller: "active_storage/blobs/redirect", action: "show",
        signed_id: "abc", filename: "x", format: "png" },
      Rails.application.routes.recognize_path("/rails/active_storage/blobs/redirect/abc/x.png")
    )
  end

  test "a one-segment path resolves to the public menu" do
    assert_equal(
      { controller: "menus", action: "show", locale: "en", restaurant_slug: "osteria-del-borgo" },
      Rails.application.routes.recognize_path("/en/osteria-del-borgo")
    )
  end

  test "a two-segment path resolves to a wine list" do
    assert_equal(
      { controller: "menus", action: "show", locale: "en",
        restaurant_slug: "osteria-del-borgo", wine_list_slug: "wine-list" },
      Rails.application.routes.recognize_path("/en/osteria-del-borgo/wine-list")
    )
  end

  # Every reserved slug must name something the routes actually claim, and
  # every top-level route must be reserved. Drift either way means an owner
  # can either claim an unreachable slug or take a path out from under a real
  # route.
  test "every reserved slug is rejected by the Restaurant model" do
    Restaurant::RESERVED_SLUGS.each do |slug|
      restaurant = Restaurant.new(
        user: users(:owner), name: "Test", address: "Via Test 1", slug: slug
      )
      assert_not restaurant.valid?, "#{slug.inspect} should be reserved"
      assert restaurant.errors.of_kind?(:slug, :exclusion)
    end
  end
end
