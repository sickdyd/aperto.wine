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

  # Below `lg` the owner shell pins a navbar to the top edge, and the drawer
  # button in it is the only route to the menu. A toast at y=0 covers it: the
  # button is still there and still looks pressable, and does nothing.
  test "a toast never covers the owner drawer button" do
    was = current_window.size
    # Chrome will not go below ~500px wide; anything under the lg breakpoint
    # shows the navbar, which is all this needs.
    current_window.resize_to(430, 900)

    sign_in_as @owner

    assert_selector ".toast-band"
    assert_operator evaluate_script("window.innerWidth"), :<, 1024,
      "the navbar is lg:hidden; above the breakpoint there is nothing to cover"

    topmost = evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector("label[for=owner-drawer]").getBoundingClientRect()
        const el = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
        return el.closest(".toast-stack") ? "toast" : "drawer button"
      })()
    JS

    assert_equal "drawer button", topmost,
      "the toast is on top of the drawer button — on a phone that is the " \
      "only way to reach the owner menu"
  ensure
    current_window.resize_to(*was) if was
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
  test "dismissing twice still removes the band once" do
    sign_in_as @owner

    assert_selector ".toast-band"
    find(".toast-dismiss").double_click

    assert_no_selector ".toast-band"
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
