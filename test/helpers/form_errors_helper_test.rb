require "test_helper"

class FormErrorsHelperTest < ActionView::TestCase
  def builder_for(wine)
    ActionView::Helpers::FormBuilder.new(:wine, wine, view, {})
  end

  def invalid_wine
    wine = Wine.new
    wine.validate
    wine
  end

  test "a valid attribute gets no aria-invalid and renders no error" do
    f = builder_for(Wine.new(name: "Barolo"))

    assert_equal({}, field_error_attributes(f, :name))
    assert_nil field_errors(f, :name)
  end

  test "an invalid attribute is marked invalid and described by its message" do
    f = builder_for(invalid_wine)

    attributes = field_error_attributes(f, :name)

    assert_equal "true", attributes["aria-invalid"]
    assert_equal "wine_name_error_0", attributes["aria-describedby"]
    assert_dom_equal %(<p class="field-error" id="wine_name_error_0">can't be blank</p>),
      field_errors(f, :name)
  end

  test "every message of a multi-error attribute is described and rendered" do
    wine = Wine.new
    wine.errors.add(:price_bottle_cents, "must be a number")
    wine.errors.add(:price_bottle_cents, "must be positive")
    f = builder_for(wine)

    attributes = field_error_attributes(f, :price_bottle_cents)

    assert_equal "wine_price_bottle_cents_error_0 wine_price_bottle_cents_error_1",
      attributes["aria-describedby"]
    assert_equal %w[wine_price_bottle_cents_error_0 wine_price_bottle_cents_error_1],
      field_error_ids(f, :price_bottle_cents)
  end

  test "a hint stays described alongside the error messages" do
    wine = Wine.new(available_glasses: -1)
    wine.validate
    f = builder_for(wine)

    described_by = field_error_attributes(f, :available_glasses, describedby: "wine_available_glasses_hint")

    assert_equal "wine_available_glasses_hint wine_available_glasses_error_0",
      described_by["aria-describedby"]
  end

  test "a hint is described even when the attribute is valid, without aria-invalid" do
    f = builder_for(Wine.new)

    attributes = field_error_attributes(f, :position, describedby: "wine_position_hint")

    assert_nil attributes["aria-invalid"]
    assert_equal "wine_position_hint", attributes["aria-describedby"]
  end

  test "error messages are escaped rather than injected as markup" do
    wine = Wine.new
    wine.errors.add(:name, "<script>alert(1)</script>")

    assert_includes field_errors(builder_for(wine), :name), "&lt;script&gt;"
  end
end
