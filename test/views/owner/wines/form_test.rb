require "test_helper"

module Owner
  module Wines
    class FormTest < ActionView::TestCase
      setup do
        # Routes are wrapped in an optional `(:locale)` scope, which the real
        # controller fills in through `default_url_options`. Without it the
        # first positional argument of `owner_restaurant_wines_path` would be
        # read as the locale.
        @controller.singleton_class.define_method(:default_url_options) { { locale: nil } }
        @restaurant = restaurants(:osteria)
      end

      def render_form(wine)
        render partial: "owner/wines/form", locals: { wine: wine }
      end

      def wine_with_errors(**errors)
        wine = @restaurant.wines.build(bottle_size_ml: 750)
        errors.each { |attribute, message| wine.errors.add(attribute, message) }
        wine
      end

      test "an invalid field is marked invalid and points at its own message" do
        render_form wine_with_errors(price_bottle_cents: "must be a number")

        assert_select "input#wine_price_bottle_cents[aria-invalid=?]", "true"
        assert_select "input#wine_price_bottle_cents[aria-describedby=?]", "wine_price_bottle_cents_error_0"
        assert_select "p.field-error#wine_price_bottle_cents_error_0", "must be a number"
      end

      test "fields without errors are not marked invalid" do
        render_form wine_with_errors(price_bottle_cents: "must be a number")

        assert_select "input#wine_region[aria-invalid]", false
        assert_select "input#wine_vintage_year[aria-invalid]", false
        assert_select "p.field-error", 1
      end

      # The colour picker takes its error attributes in `select`'s fourth
      # positional argument, so a slip there would silently drop the styling
      # rather than raise.
      test "the color select keeps its classes and autofill target" do
        render_form wine_with_errors(color: "is not included in the list")

        assert_select "select#wine_color.select[data-wine-autofill-target=?]", "color"
        assert_select "select#wine_color[aria-invalid=?]", "true"
        assert_select "select#wine_color[aria-describedby=?]", "wine_color_error_0"
      end

      # A hint that is only announced while the field is in an error state is a
      # regression against the plain markup, where it was always readable.
      test "hints stay associated with their field when there is nothing wrong" do
        render_form @restaurant.wines.build(bottle_size_ml: 750)

        assert_select "p.field-error", false
        assert_select "input#wine_available_glasses[aria-invalid]", false
        assert_select "input#wine_available_glasses[aria-describedby=?]", "wine_available_glasses_hint"
        assert_select "p.field-hint#wine_available_glasses_hint"

        ::Wine::GLASS_SIZES.each do |size|
          assert_select "input#wine_price_#{size}ml_cents[aria-describedby=?]", "wine_glass_prices_hint"
        end
        assert_select "p.field-hint#wine_glass_prices_hint"
      end

      test "a hint survives alongside the error message rather than being replaced" do
        render_form wine_with_errors(available_glasses: "must be greater than or equal to 0")

        assert_select "input#wine_available_glasses[aria-describedby=?]",
          "wine_available_glasses_hint wine_available_glasses_error_0"
        assert_select "p.field-hint#wine_available_glasses_hint"
        assert_select "p.field-error#wine_available_glasses_error_0"
      end

      test "each glass-size price owns a unique input id and a unique error id" do
        wine = wine_with_errors
        ::Wine::GLASS_SIZES.each { |size| wine.errors.add(:"price_#{size}ml_cents", "must be a number") }
        render_form wine

        ::Wine::GLASS_SIZES.each do |size|
          assert_select "input#wine_price_#{size}ml_cents[name=?]", "wine[price_#{size}ml_cents]"
          assert_select "input#wine_price_#{size}ml_cents[aria-invalid=?]", "true"
          assert_select "input#wine_price_#{size}ml_cents[aria-describedby=?]",
            "wine_glass_prices_hint wine_price_#{size}ml_cents_error_0"
          assert_select "p.field-error#wine_price_#{size}ml_cents_error_0"
        end

        ids = css_select("p.field-error").map { |node| node["id"] }
        assert_equal ids.uniq, ids
      end

      test "the top-of-form error summary survives alongside the inline errors" do
        render_form wine_with_errors(vintage_year: "is not a valid year")

        assert_select "div[role=alert] p", /Vintage is not a valid year/
        assert_select "input#wine_vintage_year[aria-describedby=?]", "wine_vintage_year_error_0"
        assert_select "p.field-error#wine_vintage_year_error_0", "is not a valid year"
      end

      test "the autofill wiring is untouched by the error attributes" do
        render_form wine_with_errors(name: "can't be blank")

        assert_select "form[data-controller=?]", "wine-autofill"
        assert_select "input#wine_name[data-wine-autofill-target=?]", "input"
        assert_select "input#wine_name[aria-controls=?]", "wine-suggestions-listbox"
        assert_select "input#wine_name[aria-invalid=?]", "true"
        assert_select "input#wine_name[aria-describedby=?]", "wine_name_error_0"
        %w[producer grape color vintage region].each do |target|
          assert_select "[data-wine-autofill-target=?]", target
        end
      end
    end
  end
end
