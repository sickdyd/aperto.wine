require "application_system_test_case"

# The order-sound preference, in a real browser.
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
# What is asserted is the part that is real and checkable. Two halves, and the
# seam between them is where this feature can actually break:
#
#   * THE CONTROL, which lives on the restaurant settings page and nowhere
#     else. It changes state on a click, and — the part a localStorage
#     preference actually tends to get wrong — it reports "blocked" rather than
#     "on" after a reload has left the preference set and the audio not yet
#     granted, then repairs itself on the next interaction.
#   * THE CHIME, which does not depend on the control being on the page at all.
#     Every other owner page — the orders board above all, which is the page
#     this feature exists for — carries no control. The controller is mounted
#     on the shell and reads the preference out of localStorage, so a page with
#     nothing to show must still arm, repair and announce. That is the one
#     thing nothing else in this suite would catch, and it has its own test
#     below.
module Owner
  class OrderSoundTest < ApplicationSystemTestCase
    TOGGLE = Owner::OrdersHelper::SOUND_TOGGLE_ID

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

    # The one page that carries the control.
    def visit_settings
      visit edit_owner_restaurant_path(id: @restaurant)
      assert_text I18n.t("owner.restaurants.edit_title"), wait: 5
    end

    # Somewhere inside the restaurant that is NOT the settings page and not the
    # orders board: an ordinary owner page, with the shell's controller mounted
    # and no control anywhere on it. This is what most of the dashboard looks
    # like now, so most of the chime's behaviour has to be provable from here.
    def visit_dashboard
      visit owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_text I18n.t("owner.wines.title"), wait: 5
    end

    # No explicit wait: bringing an AudioContext up is the browser talking to
    # an audio device, and on a loaded machine that is not instant. The default
    # Capybara wait is the one tuned for this repo's machines.
    def assert_sound_state(state)
      assert_selector "##{TOGGLE}[data-sound-state='#{state}']", visible: :all
    end

    # What the controller itself thinks, asked directly. Needed because most
    # owner pages have no control to read the state off — that is the whole
    # point of the change this file guards — so the DOM cannot answer for them.
    def sound_controller_state
      page.evaluate_script(<<~JS)
        (() => {
          const shell = document.querySelector("[data-controller~='order-sound']")
          if (!shell) return "no-controller"
          const controller = window.Stimulus.getControllerForElementAndIdentifier(shell, "order-sound")
          return controller ? controller.state : "not-connected"
        })()
      JS
    end

    # evaluate_script does no waiting of its own and resuming an AudioContext is
    # asynchronous, so poll it the way Capybara polls the DOM, on the same
    # budget. Asserting once would be a race on a loaded machine.
    def assert_sound_reported(state)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
      actual = nil

      loop do
        actual = sound_controller_state
        break if actual == state || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.1
      end

      assert_equal state, actual
    end

    # Counting oscillators is the only proof available that the chime ran: the
    # tone is synthesised, so nothing is fetched and nothing lands in the DOM.
    # Patching the prototype reaches the context that already exists, which
    # matters — the module keeps one per document and never rebuilds it.
    def count_chime_voices
      page.execute_script(<<~JS)
        window.__voices = 0
        const create = AudioContext.prototype.createOscillator
        AudioContext.prototype.createOscillator = function (...args) {
          window.__voices += 1
          return create.apply(this, args)
        }
      JS
    end

    def chime_voices
      page.evaluate_script("window.__voices")
    end

    def place_order
      Order.create!(
        restaurant: @restaurant, restaurant_table: restaurant_tables(:sala_t1),
        status: :pending, total_amount_cents: 2400
      )
    end

    # ── The control ──────────────────────────────────────────────────────────

    # It is a setting, so it lives with the settings. The chrome carried it
    # while it was thought of as a companion to the pending badge; a badge is a
    # reading you need in front of you wherever you are, a preference is set
    # once per device and then left alone. Asserted from both ends, because
    # "moved" is only half done if a copy stayed behind.
    test "the control is on the settings page and nowhere in the chrome" do
      visit_settings

      assert_selector "##{TOGGLE}", visible: :all
      assert_no_selector ".drawer-side aside ##{TOGGLE}", visible: :all
      assert_no_selector "header ##{TOGGLE}", visible: :all

      visit_dashboard
      assert_no_selector "[data-order-sound-target='toggle']", visible: :all
    end

    test "sound starts off, and the control says so rather than assuming" do
      visit_settings

      assert_sound_state "off"
      assert_equal "false", find("##{TOGGLE}", visible: :all)["aria-pressed"]
      assert_selector "##{TOGGLE}", text: I18n.t("owner.orders.sound.disabled"), visible: :all
    end

    # A click is a real user gesture as far as the browser is concerned, which
    # is the only condition under which an AudioContext will start — so what
    # this asserts is not merely a class swap, it is that the audio actually
    # came up. A context that stayed suspended would report "blocked" here.
    test "switching sound on reports it on" do
      visit_settings

      find("##{TOGGLE}").click

      assert_sound_state "on"
      assert_equal "true", find("##{TOGGLE}", visible: :all)["aria-pressed"]
      assert_selector "##{TOGGLE}", text: I18n.t("owner.orders.sound.enabled"), visible: :all
    end

    test "switching it back off reports it off" do
      visit_settings

      find("##{TOGGLE}").click
      assert_sound_state "on"

      find("##{TOGGLE}").click
      assert_sound_state "off"
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
      visit_settings
      find("##{TOGGLE}").click
      assert_sound_state "on"

      visit_settings

      assert_sound_state "blocked"
      assert_equal "false", find("##{TOGGLE}", visible: :all)["aria-pressed"]
    end

    # ...and it repairs itself on the first interaction with the page, whatever
    # that interaction is, so staff do not have to find the toggle again after
    # every reload — the browser only ever wanted a gesture, not that gesture.
    test "the first interaction after a reload restores the sound" do
      visit_settings
      find("##{TOGGLE}").click
      assert_sound_state "on"

      visit_settings
      assert_sound_state "blocked"

      find("h1", match: :first).click

      assert_sound_state "on"
    end

    # ── The chime, away from the control ─────────────────────────────────────

    # THE REGRESSION THIS FILE EXISTS FOR since the control moved.
    #
    # The orders board carries no control. Neither does the wines page standing
    # in for it here. If the controller treats "no toggle on this page" as
    # "nothing to do" — which is exactly what its old `if (!this.hasToggleTarget)
    # return` did, back when the shell rendered a toggle on every page and the
    # guard only ever fired outside a restaurant — then the gesture listener is
    # never armed, the blocked context is never repaired, and an order arriving
    # on the one screen the kitchen is watching makes no sound at all. Every
    # other test in this file would still pass.
    #
    # So: turn it on where the control is, load a page where it is not, and
    # prove the whole chain still runs there — the preference survives, a
    # gesture lifts the block, and an arriving order is answered with a tone.
    test "a page with no control repairs its blocked audio and still chimes" do
      visit_settings
      find("##{TOGGLE}").click
      assert_sound_state "on"

      visit_dashboard
      assert_no_selector "[data-order-sound-target='toggle']", visible: :all

      # A full load is a new document, so the browser has withdrawn audio again
      # and there is nothing on the page to say so. The controller still knows.
      assert_sound_reported "blocked"

      count_chime_voices
      find("h1", match: :first).click
      assert_sound_reported "on"

      order = place_order
      assert_selector ".toast-band", text: "##{order.id}", wait: 10

      assert_operator chime_voices, :>, 0,
        "the order was announced on screen but nothing was played, so the room hears nothing"
    end

    # A Turbo visit is the common case during service, and the one where an
    # AudioContext owned by the controller instance would be thrown away and
    # rebuilt suspended — silently dropping the sound on the first nav click.
    # Now also the case where the control is left behind on the page it lives
    # on, so the state has to be asked of the controller rather than the DOM.
    test "the sound survives moving off the settings page" do
      visit_settings
      find("##{TOGGLE}").click
      assert_sound_state "on"

      click_link I18n.t("owner.restaurants.tables"), match: :first
      assert_text I18n.t("owner.restaurants.tables"), wait: 5

      assert_no_selector "[data-order-sound-target='toggle']", visible: :all
      assert_sound_reported "on"
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

      order = place_order

      assert_selector "body[data-announced-orders='#{order.id}']", visible: :all

      # The poller runs every second under test, so a repeat would land well
      # inside this wait.
      assert_no_selector "body[data-announced-orders='#{order.id},#{order.id}']",
        visible: :all, wait: 3
    end

    # The other half of that seam, which nothing else would catch: the shell
    # has to be listening. Renaming the event on either side compiles, passes
    # every other test here, and silently stops the room hearing anything.
    #
    # Asserted on an ordinary page rather than on settings, deliberately: the
    # listener belongs to the shell, and the shell is everywhere.
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
      assert_sound_reported "off"

      order = place_order

      assert_selector ".toast-band", text: "##{order.id}", wait: 10
    end

    # ── The iPad at the pass ─────────────────────────────────────────────────

    # As far as a browser test can carry it.
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
      visit_settings

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

      find("##{TOGGLE}").click
      assert_sound_state "on"

      assert_operator page.evaluate_script("window.__played"), :>=, 1,
        "nothing was played through a media element, so an old iPad would stay silenced"
    end
  end
end
