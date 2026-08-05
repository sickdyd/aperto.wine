require "application_system_test_case"

# The floating flash, in a real browser. The static guards in
# test/deploy/flash_toast_test.rb check the CSS says the right things; these
# check the browser agrees — that the band is genuinely out of flow and that
# the dismiss button genuinely removes it.
class FlashTest < ApplicationSystemTestCase
  setup do
    @owner = users(:owner)
  end

  def sign_in_as(user)
    visit sign_in_path
    fill_in I18n.t("auth.email"), with: user.email
    fill_in I18n.t("auth.password"), with: "password123"
    click_button I18n.t("auth.sign_in")
  end

  # Document coordinates, so a stray scroll cannot masquerade as a reflow.
  def main_offset_top
    evaluate_script(
      "document.querySelector('main').getBoundingClientRect().top + window.scrollY"
    )
  end

  test "the owner flash floats instead of pushing the page down" do
    sign_in_as @owner

    assert_current_path owner_restaurants_path
    assert_selector ".toast-band", text: /#{Regexp.escape(I18n.t("auth.signed_in"))}/i
    assert_equal "fixed",
      evaluate_script("getComputedStyle(document.querySelector('.toast-stack')).position")

    with_flash = main_offset_top

    # Same page, same layout — the flash has been consumed by the first render.
    visit owner_restaurants_path
    assert_no_selector ".toast-stack"

    assert_in_delta with_flash, main_offset_top, 1,
      "the flash moved <main>; a floating toast must cost the page no space"
  end

  test "the public flash floats too" do
    # Unauthenticated: redirected to sign in, through the public layout, with an alert.
    visit owner_restaurants_path

    assert_current_path sign_in_path
    assert_selector ".toast-band", text: /#{Regexp.escape(I18n.t("auth.sign_in_required"))}/i
    assert_equal "fixed",
      evaluate_script("getComputedStyle(document.querySelector('.toast-stack')).position")
  end

  # An invisible full-width fixed container across the top of every page is a
  # dead zone if it keeps its pointer events — the sign-in link sits right under it.
  test "the empty stack does not swallow clicks on the page beneath it" do
    visit sign_in_path

    assert_no_selector ".toast-stack"
    click_link I18n.t("auth.sign_up_link")

    assert_current_path sign_up_path
  end

  # Tailwind emits a rule only for class strings it can find in the source, so
  # a variant assembled at render time gets no rule at all and the band falls
  # back to the plain `.alert` ground. Everything else about it still looks
  # right, which is why this is asserted against the browser and not the CSS:
  # the question is what the band actually ends up painted, not what was typed.
  test "the success band keeps a ground of its own" do
    sign_in_as @owner

    assert_selector ".toast-band"
    band, page_bg = evaluate_script(<<~JS)
      [
        getComputedStyle(document.querySelector(".toast-band")).backgroundColor,
        getComputedStyle(document.body).backgroundColor
      ]
    JS

    refute_equal page_bg, band,
      "the success band is painted in the page's own paper stock — the " \
      "alert-success rule was never emitted"
  end

  # The menu's cart bar is the one piece of chrome already pinned to the bottom
  # edge, and the corner the toast now occupies is its right-hand end — where
  # the link to the cart is. This is the every-time case, not an edge case:
  # adding to the cart redirects back to the menu with a notice, so both are
  # drawn on the same render.
  #
  # The clearance is a measured constant in the stylesheet, so what is asserted
  # here is the thing that actually matters — that the two boxes do not
  # overlap — rather than the number itself, which may legitimately change.
  test "a toast never lands on the menu's cart bar" do
    barolo = wines(:barolo)
    visit menu_path(id: restaurants(:osteria))

    find("button[aria-label='#{I18n.t("menu.add_to_cart", wine: barolo.name, size: 125)}']").click

    assert_selector "#cart-bar"
    assert_selector ".toast-band"

    overlap = evaluate_script(<<~JS)
      (() => {
        const toast = document.querySelector(".toast-stack").getBoundingClientRect()
        const bar = document.querySelector("#cart-bar").getBoundingClientRect()
        return !(toast.bottom <= bar.top || toast.top >= bar.bottom ||
                 toast.right <= bar.left || toast.left >= bar.right)
      })()
    JS

    refute overlap,
      "the toast overlaps the cart bar — the bar carries the link to the " \
      "cart, and it is drawn on the very render that shows this notice"
  end

  # The bar only exists once the cart holds something; the rest of the time
  # the toast should be using the corner it was given.
  test "the cart-bar clearance is not paid on pages without one" do
    sign_in_as @owner
    assert_selector ".toast-band"

    gap = evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector(".toast-stack").getBoundingClientRect()
        return window.innerHeight - r.bottom
      })()
    JS

    assert_in_delta 0, gap, 1,
      "the stack is sitting off the bottom edge on a page with no cart bar"
  end

  test "a band can be dismissed" do
    sign_in_as @owner

    assert_selector ".toast-band"
    assert_selector ".toast-dismiss[aria-label='#{I18n.t("shared.flash_dismiss")}']"

    find(".toast-dismiss").click

    assert_no_selector ".toast-band"
  end

  # Pressing the close button twice, or pressing it at the moment the
  # auto-dismiss timer fires, must not restart the removal timer and hold an
  # invisible band in the document for another fade.
  #
  # Asserted on the timer rather than on the band going away, because the band
  # goes away either way: a second dismiss only pushes removal out by one more
  # fade, and no `assert_no_selector` wait short enough to notice 180ms is one
  # this suite could rely on. The question is whether the second call is inert,
  # so that is what gets asked — directly, through the controller.
  test "a second dismiss is inert rather than restarting the removal timer" do
    sign_in_as @owner
    assert_selector ".toast-band"

    first, second = evaluate_script(<<~JS)
      (() => {
        const band = document.querySelector(".toast-band")
        const flash = window.Stimulus.getControllerForElementAndIdentifier(band, "flash")
        flash.dismiss()
        const first = flash.removalTimer
        flash.dismiss()
        return [first, flash.removalTimer]
      })()
    JS

    assert first, "the first dismiss did not arm a removal timer"
    assert_equal first, second,
      "the second dismiss armed a new removal timer, holding an invisible " \
      "band in the document for another fade"
  end

  # Turbo paints the cached snapshot of the previous page on back/forward
  # before the fresh response arrives. A flash left in that snapshot slides
  # back in with a fresh timer and reads as a new notification.
  test "going back does not replay a flash the reader already saw" do
    sign_in_as @owner
    assert_selector ".toast-band"

    # A Turbo navigation, so leaving here is what fills the snapshot cache.
    click_link restaurants(:osteria).name
    assert_no_selector ".toast-band"

    page.go_back

    assert_current_path owner_restaurants_path
    assert page.has_no_selector?(".toast-band"),
      "the toast came back from Turbo's cache — it needs data-turbo-temporary"
  end
end
