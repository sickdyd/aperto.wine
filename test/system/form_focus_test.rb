require "application_system_test_case"

# The focus indicator on a ruled field is pure CSS, and the CSS that draws it has
# to win a cascade-layer fight against daisyUI to exist at all (see the unlayered
# reskin section in application.css). Nothing in the Ruby layer can catch a
# regression there, and the failure mode is silent: the field quietly goes back
# to wearing daisyUI's near-black ring on every mouse click and nobody notices
# until someone looks at a screenshot. getComputedStyle in a real browser is the
# only place the answer exists, so that is what these assert against.
class FormFocusTest < ApplicationSystemTestCase
  RULE_HEAVY = "rgb(74, 18, 25)".freeze  # --color-rule-heavy: the focused rule
  STOCK = "rgb(232, 220, 198)".freeze    # --color-stock: the focused blank's ground
  OX_2 = "rgb(110, 31, 42)".freeze       # --color-ox-2: the ring on things that are boxes
  OX_5 = "rgb(232, 213, 214)".freeze     # --color-ox-5: the same ring, on a deep ground

  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text I18n.t("owner.restaurants.title"), wait: 5
  end

  def style(element, property)
    page.evaluate_script(
      "window.getComputedStyle(arguments[0]).getPropertyValue(arguments[1])",
      element,
      property
    )
  end

  # Sent to whatever holds focus right now, so several tabs can be chained
  # without re-finding the node that happens to hold focus after each one.
  def press_tab
    page.driver.browser.switch_to.active_element.send_keys(:tab)
  end

  # Walks the document's real tab order instead of assuming a number of stops:
  # only a key press makes the ring warranted on a link, and how many stops sit
  # before one is a detail of the page, not of the treatment under test.
  def tab_to(element, limit: 12)
    limit.times do
      press_tab
      return if page.evaluate_script("document.activeElement === arguments[0]", element)
    end

    flunk "keyboard focus never reached #{element.tag_name}.#{element[:class]} in #{limit} tabs"
  end

  # Identity, not id: `f.submit` renders no id at all, and comparing two blank
  # strings would pass however focus actually landed.
  def assert_focused(element)
    assert page.evaluate_script("document.activeElement === arguments[0]", element),
      "expected focus on #{element.tag_name}#{element[:id].present? ? "##{element[:id]}" : ''}"
  end

  # No ring; a shaded stock and a deepened rule instead. `box-shadow: none` is
  # asserted too — daisyUI hangs a black one on the same `:focus`, and the ledger
  # forbids shadows outright (test/deploy/ledger_theme_test.rb).
  def assert_ruled_focus(field)
    assert_equal "none", style(field, "outline-style")
    assert_equal "none", style(field, "box-shadow")
    assert_equal RULE_HEAVY, style(field, "border-bottom-color")
    assert_equal STOCK, style(field, "background-color")
  end

  # ── Ruled fields: no ring, a shaded blank and a deeper rule ────────────────

  test "clicking a text field shades the blank instead of drawing a ring" do
    sign_in_as_owner
    visit edit_owner_restaurant_path(id: restaurants(:osteria))

    field = find("#restaurant_name")
    unfocused_rule = style(field, "border-bottom-color")
    unfocused_ground = style(field, "background-color")

    field.click
    assert_focused field
    assert_ruled_focus field

    # The indicator has to be a *change*, not merely a colour that happens to be
    # oxblood: an unfocused field already carries a red rule, and is transparent
    # rather than white, so neither half of the treatment is a no-op.
    refute_equal unfocused_rule, style(field, "border-bottom-color")
    refute_equal unfocused_ground, style(field, "background-color")
  end

  test "clicking a textarea shades the blank instead of drawing a ring" do
    sign_in_as_owner
    visit edit_owner_restaurant_path(id: restaurants(:osteria))

    field = find("#restaurant_description")
    field.click

    assert_focused field
    assert_ruled_focus field
  end

  # A field also matches :focus-visible on a pointer press, because it takes
  # keyboard input — which is exactly why the ring could not simply be narrowed
  # to :focus-visible and left oxblood. Tabbing in must land on the same
  # treatment rather than resurrect an outline.
  test "tabbing into a text field draws no ring either" do
    sign_in_as_owner
    visit edit_owner_restaurant_path(id: restaurants(:osteria))

    find("#restaurant_name").click
    press_tab

    slug = find("#restaurant_slug")
    assert_focused slug
    assert_ruled_focus slug
  end

  # Chrome's customizable-select model paints the drop-down with the control's
  # own background, and the control stays focused for as long as the picker is
  # open. A translucent focus ground would therefore show the page through the
  # option list — the exact bug the select is styled apart from the other fields
  # to avoid.
  test "a focused select keeps an opaque ground" do
    sign_in_as_owner
    visit new_owner_restaurant_wine_path(restaurant_id: restaurants(:osteria))

    # Focused programmatically rather than clicked: a click on a customizable
    # select opens the picker, and the picker takes the active element with it, so
    # a click cannot be used to observe the closed control's focused state.
    field = find("#wine_color")
    page.evaluate_script("arguments[0].focus()", field)

    assert_focused field
    assert_equal "none", style(field, "outline-style")
    assert_equal STOCK, style(field, "background-color")
  end

  # ── Boxes keep the ring, in the ledger's own oxblood ───────────────────────

  # The fix narrows the ring away from fields; it must not have taken it off the
  # controls that *are* boxes, nor left them ringed in the ink black daisyUI
  # reaches for. Walked by keyboard from the last field in the form: a toggle and
  # a submit button ring only when focus was warranted by a key press.
  test "a toggle and a button reached by keyboard carry an oxblood ring" do
    sign_in_as_owner
    visit edit_owner_restaurant_path(id: restaurants(:osteria))

    find("#restaurant_proximity_radius_meters").click
    press_tab

    toggle = find("#restaurant_active")
    assert_focused toggle
    assert_equal "solid", style(toggle, "outline-style")
    assert_equal OX_2, style(toggle, "outline-color")

    press_tab

    submit = find("input[type='submit']")
    assert_focused submit
    assert_equal "solid", style(submit, "outline-style")
    assert_equal OX_2, style(submit, "outline-color")
  end

  # The masthead is the one deep band on the site, and a core-oxblood ring is
  # near-invisible on it — the base rule flips the ring to the tint there for
  # exactly that reason. `@apply btn` defeated that flip along with everything
  # else, by landing daisyUI's own `outline-color` in @layer components ahead of
  # it, so the flip is restated at that specificity. This is what proves it took.
  test "a masthead button reached by keyboard rings in the tint" do
    visit root_path

    button = find(".masthead a.btn-wine-deep")
    tab_to button

    assert_equal "solid", style(button, "outline-style")
    assert_equal OX_5, style(button, "outline-color")
  end
end
