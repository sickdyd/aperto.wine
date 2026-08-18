require "application_system_test_case"

# The order-sound toggle, in a real browser.
#
# WHAT THIS FILE CANNOT COVER, and no rearrangement of it would:
#
#   * that a sound is heard. Selenium cannot listen, headless Chrome renders
#     audio to a null device, and the Web Audio graph leaves nothing in the DOM
#     behind it. Whether the chime is pleasant, loud enough to carry across a
#     service room, or audible over the volume the tablet at the pass happens
#     to be set to, is a question only a human standing there can answer.
#   * that the browser's autoplay block is the *only* thing standing between a
#     suspended context and a running one. A Selenium click is a real user
#     gesture, so these tests exercise the same path a member of staff does;
#     what they cannot do is prove a device with audio genuinely muted at OS
#     level reports itself honestly, because Chrome does not distinguish it.
#
# What is asserted is the part that is real and checkable: the control is in
# both places, it changes state on a click, and — the part a localStorage
# preference actually tends to get wrong — it reports "blocked" rather than
# "on" after a reload has left the preference set and the audio not yet
# granted, then repairs itself on the next interaction.
module Owner
  class OrderSoundTest < ApplicationSystemTestCase
    SIDEBAR = Owner::OrdersHelper::SOUND_TOGGLE_IDS[:sidebar]
    MOBILE = Owner::OrdersHelper::SOUND_TOGGLE_IDS[:mobile]

    setup do
      @restaurant = restaurants(:osteria)
      sign_in_as_owner
    end

    def sign_in_as_owner
      user = users(:owner)
      visit sign_in_path
      fill_in "email", with: user.email
      fill_in "password", with: "password123"
      find("input[type='submit']").click
      assert_text I18n.t("owner.restaurants.title"), wait: 5
    end

    # Somewhere inside the restaurant, and not the orders board: the toggle
    # belongs to the shell, so it has to be on every page of it.
    def visit_dashboard
      visit owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_text I18n.t("owner.wines.title"), wait: 5
    end

    # The two copies are laid out for different viewports, so at any given
    # width one of them is display:none. Both are still asserted on — a stale
    # copy behind a drawer is exactly the bug the paired ids exist to prevent.
    def toggles
      [ find("##{SIDEBAR}", visible: :all), find("##{MOBILE}", visible: :all) ]
    end

    # No explicit wait: bringing an AudioContext up is the browser talking to
    # an audio device, and on a loaded machine that is not instant. The default
    # Capybara wait is the one tuned for this repo's machines.
    def assert_sound_state(state)
      [ SIDEBAR, MOBILE ].each do |id|
        assert_selector "##{id}[data-sound-state='#{state}']", visible: :all
      end
    end

    test "the toggle is rendered in both places the pending badge is" do
      visit_dashboard

      assert_equal Owner::OrdersHelper::BADGE_IDS.keys, Owner::OrdersHelper::SOUND_TOGGLE_IDS.keys
      assert_equal 2, toggles.size
      assert_sound_state "off"
    end

    test "sound starts off, and the control says so rather than assuming" do
      visit_dashboard

      assert_sound_state "off"
      toggles.each { |toggle| assert_equal "false", toggle["aria-pressed"] }
      assert_selector "##{SIDEBAR}", text: I18n.t("owner.orders.sound.disabled"), visible: :all
    end

    # A click is a real user gesture as far as the browser is concerned, which
    # is the only condition under which an AudioContext will start — so what
    # this asserts is not merely a class swap, it is that the audio actually
    # came up. A context that stayed suspended would report "blocked" here.
    test "switching sound on reports it on, in both copies" do
      visit_dashboard

      find("##{SIDEBAR}", visible: :all).click

      assert_sound_state "on"
      toggles.each { |toggle| assert_equal "true", toggle["aria-pressed"] }
      assert_selector "##{SIDEBAR}", text: I18n.t("owner.orders.sound.enabled"), visible: :all
    end

    test "switching it back off reports it off" do
      visit_dashboard

      find("##{SIDEBAR}", visible: :all).click
      assert_sound_state "on"

      find("##{SIDEBAR}", visible: :all).click
      assert_sound_state "off"
    end

    # The reason there are two copies at all: on a phone the sidebar is behind
    # a drawer, so the only one reachable without opening it is the one in the
    # top bar. Asserted structurally rather than by driving the browser down to
    # a phone width — headless Chrome on macOS clamps the window at ~500px and,
    # at that size, silently stops dispatching input altogether, which makes a
    # resized click a coin toss rather than a test.
    #
    # Every state assertion in this file covers both copies (see
    # assert_sound_state), so "the two never disagree" is checked throughout.
    test "each copy sits in the chrome its viewport shows" do
      visit_dashboard

      assert_selector "header.lg\\:hidden ##{MOBILE}", visible: :all
      assert_selector ".drawer-side aside ##{SIDEBAR}", visible: :all
    end

    # The point of localStorage over a session or a column: it is the device
    # that wants sound, and it wants it again tomorrow.
    #
    # It comes back as "blocked", not "on", and that is the whole feature
    # working. A full reload is a new document, and a new document has not been
    # interacted with, so the browser will not let it make a sound yet. The
    # preference is remembered; the control declines to claim more than is
    # true. A version of this that said "on" here would be the failure mode
    # worth fearing — a lit toggle over a silent room.
    test "after a reload the preference is remembered but not yet claimed as audible" do
      visit_dashboard
      find("##{SIDEBAR}", visible: :all).click
      assert_sound_state "on"

      visit owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_text I18n.t("owner.wines.title"), wait: 5

      assert_sound_state "blocked"
      toggles.each { |toggle| assert_equal "false", toggle["aria-pressed"] }
    end

    # ...and it repairs itself on the first interaction with the page, whatever
    # that interaction is, so staff do not have to find the toggle again after
    # every reload — the browser only ever wanted a gesture, not that gesture.
    test "the first interaction after a reload restores the sound" do
      visit_dashboard
      find("##{SIDEBAR}", visible: :all).click
      assert_sound_state "on"

      visit owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_sound_state "blocked"

      find("h1", match: :first).click

      assert_sound_state "on"
    end

    # A Turbo visit is the common case during service, and the one where an
    # AudioContext owned by the controller instance would be thrown away and
    # rebuilt suspended — silently dropping the sound on the first nav click.
    test "the sound survives moving around the dashboard" do
      visit_dashboard
      find("##{SIDEBAR}", visible: :all).click
      assert_sound_state "on"

      click_link I18n.t("owner.restaurants.tables"), match: :first
      assert_text I18n.t("owner.restaurants.tables"), wait: 5

      assert_sound_state "on"
    end

    # The iPad-at-the-pass case, as far as a browser test can carry it.
    #
    # On iOS the hardware ringer switch mutes Web Audio while leaving <audio>
    # alone. Safari answers that with navigator.audioSession; older Safari has
    # no such API, and there the only remedy is to start a media element inside
    # the gesture, which shifts the page off the "ambient" session. Chrome does
    # not implement audioSession, so headless Chrome takes exactly that legacy
    # branch — which makes this assertable here even though the platform it
    # exists for is not.
    #
    # What this cannot show is the effect: that the switch is actually released
    # on an iPad in silent mode. Only a human holding one can say that.
    test "enabling sound starts a silent clip for browsers without the audio session API" do
      visit_dashboard

      assert_equal false, page.evaluate_script("'audioSession' in navigator"),
        "this browser has audioSession, so the legacy branch under test never runs"

      # Patched and never restored, which is safe only because every test here
      # opens with a fresh `visit` — a new JS realm, so the patch cannot reach
      # the next case. A test added below that reuses a page across cases would
      # inherit it; say so rather than leave the invariant implicit.
      page.execute_script(<<~JS)
        window.__played = 0
        const play = HTMLMediaElement.prototype.play
        HTMLMediaElement.prototype.play = function (...args) {
          window.__played += 1
          return play.apply(this, args)
        }
      JS

      find("##{SIDEBAR}", visible: :all).click
      assert_sound_state "on"

      assert_operator page.evaluate_script("window.__played"), :>=, 1,
        "nothing was played through a media element, so an old iPad would stay silenced"
    end

    # The seam between the poller and the chime, which is the part that can
    # actually break: an order that raises a toast has to raise exactly one
    # announcement, from the poller's own window of known ids rather than from
    # any second notion of newness. What happens after the event — whether a
    # sound comes out — is the part no browser test can reach.
    test "an arriving order is announced once, and only once" do
      visit_dashboard

      page.execute_script(<<~JS)
        window.addEventListener("order-notifications:new-orders", (event) => {
          const seen = (document.body.dataset.announcedOrders || "").split(",").filter(Boolean)
          document.body.dataset.announcedOrders = seen.concat(event.detail.ids).join(",")
        })
      JS

      order = Order.create!(
        restaurant: @restaurant, restaurant_table: restaurant_tables(:sala_t1),
        status: :pending, total_amount_cents: 2400
      )

      assert_selector "body[data-announced-orders='#{order.id}']", visible: :all

      # The poller runs every second under test, so a repeat would land well
      # inside this wait.
      assert_no_selector "body[data-announced-orders='#{order.id},#{order.id}']",
        visible: :all, wait: 3
    end

    # The other half of that seam, which nothing else would catch: the shell
    # has to be listening. Renaming the event on either side compiles, passes
    # every other test here, and silently stops the room hearing anything.
    test "the shell listens for arriving orders on the sound control's behalf" do
      visit_dashboard

      assert_selector "[data-controller~='order-sound']" \
        "[data-action='order-notifications:new-orders@window->order-sound#announce']",
        visible: :all
    end

    # The toast is the announcement staff can rely on when the room is loud,
    # the tab is muted at OS level, or nobody can hear it. Sound is additive,
    # and a regression that traded one for the other would pass every other
    # test in this file.
    test "an arriving order still raises its toast with sound off" do
      visit_dashboard
      assert_sound_state "off"

      order = Order.create!(
        restaurant: @restaurant, restaurant_table: restaurant_tables(:sala_t1),
        status: :pending, total_amount_cents: 2400
      )

      assert_selector ".toast-band", text: "##{order.id}", wait: 10
    end
  end
end
