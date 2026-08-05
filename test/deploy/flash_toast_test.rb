require "test_helper"

# The flash is the one piece of chrome that arrives unannounced and is drawn on
# top of a page it knows nothing about. Almost everything that can go wrong with
# it is invisible to a request spec and expensive to catch in a browser: a stack
# that reflows the page, an invisible fixed container that swallows clicks on
# the content beneath it, a z-index that loses to the owner drawer, a fixed
# overlay printed across a sheet of QR cards. These guard the contract as text.
class FlashToastTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/tailwind/application.css")
  PUBLIC_FLASH = Rails.root.join("app/views/shared/_flash.html.erb")
  OWNER_FLASH = Rails.root.join("app/views/owner/shared/_flash.html.erb")
  BAND_PARTIAL = Rails.root.join("app/views/shared/_flash_band.html.erb")
  CONTROLLER = Rails.root.join("app/javascript/controllers/flash_controller.js")

  # The stack has to clear everything already pinned to the viewport: the owner
  # drawer (z-50), the owner mobile navbar (z-40), the public cart bar (z-30).
  DRAWER_Z_INDEX = 50

  # Where the deliberately unlayered daisyUI reskins begin. Kept as its own
  # constant rather than reached for on LedgerThemeTest: sibling test classes
  # are only loaded when the whole suite runs, so borrowing one makes this file
  # pass in a full run and error out on its own.
  UNLAYERED_MARKER = "daisyUI reskins — deliberately UNLAYERED".freeze

  setup do
    @css = STYLESHEET.read
    @public_flash = PUBLIC_FLASH.read
    @owner_flash = OWNER_FLASH.read
    @band = BAND_PARTIAL.read
    @controller = CONTROLLER.read
  end

  # The declaration block, not the `@media print` restatement further down.
  def stack_block
    @stack_block ||= @css[/^\s*\.toast-stack\s*\{[^}]*\}/m]
  end

  def band_blocks
    @css.scan(/^\s*\.toast-band[^{]*\{[^}]*\}/m).join("\n")
  end

  test "the stack is taken out of flow entirely" do
    assert stack_block, ".toast-stack is missing from the stylesheet"
    assert_match(/position:\s*fixed/, stack_block,
      "a flash must never reflow the page it interrupts — the whole point of " \
      "the rewrite was that an in-flow banner pushed the layout down")
  end

  test "the stack outranks every other pinned surface" do
    z = stack_block[/z-index:\s*(\d+)/, 1]
    assert z, ".toast-stack declares no z-index"
    assert_operator z.to_i, :>, DRAWER_Z_INDEX,
      "the owner drawer-side is z-#{DRAWER_Z_INDEX}; a flash drawn under it is a flash nobody reads"
  end

  test "the stack is click-through but its bands are not" do
    assert_match(/pointer-events:\s*none/, stack_block,
      "the stack spans the top of the viewport whether or not it holds a " \
      "band; without this it eats clicks on the page beneath it")
    assert_match(/pointer-events:\s*auto/, band_blocks,
      "the band itself carries a dismiss button and must stay clickable")
  end

  test "the stack is centred and bounded rather than edge to edge" do
    assert_match(/max-width:\s*42rem/, stack_block)
    assert_match(/margin-inline:\s*auto/, stack_block)
    assert_match(/padding:\s*[^;]+/, stack_block,
      "the padding is the small-screen gutter — a band flush to both edges " \
      "of a phone reads as a system bar, not as a message")
  end

  test "the toast keeps the ledger's flat vocabulary" do
    toast_css = [ stack_block, band_blocks, @css[/^\s*\.toast-dismiss\s*\{[^}]*\}/m].to_s ].join("\n")

    refute_match(/border-radius:\s*(?!0)/, toast_css,
      "the ledger has no corners, and a floating band is not the exception")
    refute_match(/box-shadow:(?!\s*none)/, toast_css,
      "separation from the page comes from a ruled edge, never from a blur")
  end

  test "the floating band is ruled on every edge" do
    assert_match(/border-top:\s*1px solid/, band_blocks,
      "the page scrolls underneath the band, so it needs a closed edge to " \
      "read as its own object; .alert.alert supplies only the 4px left rule")
    assert_match(/border-right:\s*1px solid/, band_blocks)
    assert_match(/border-bottom:\s*1px solid/, band_blocks)
  end

  # .alert.alert lives unlayered and zeroes border-width. A `.toast-band` rule
  # written in @layer components would lose to it outright, and even unlayered
  # a single class loses on specificity — hence the doubled class.
  test "the band's edge rules are declared where they can actually win" do
    layered, unlayered = @css.split(UNLAYERED_MARKER, 2)

    assert unlayered, "the unlayered reskin section is missing from the stylesheet"
    assert_match(/^\.toast-band\.toast-band\s*\{/, unlayered,
      ".toast-band's borders must outrank the unlayered `.alert.alert` reskin, " \
      "which sets border-width: 0 — a layered or single-class rule is dead here")
    refute_match(/^\s+\.toast-band[^{]*\{[^}]*border-(?:top|right|bottom):/m, layered,
      "border rules for the band inside @layer components are silently " \
      "overridden by the unlayered .alert.alert reskin")
  end

  # Tailwind builds its stylesheet from the class strings it can find by
  # scanning the source, so a class assembled at render time is a class it
  # never emits a rule for. `alert-<%= state %>` cost every success flash its
  # green ground — and nothing failed, because the band still had its label,
  # its icon and its layout. `alert-error` masked it further: six other views
  # spell that one out literally, so only success went pale.
  test "the band's colour variants are written out, never assembled" do
    refute_match(/class="[^"]*alert-<%/, @band,
      "an interpolated variant is invisible to Tailwind's scanner and the " \
      "rule is silently never emitted — pass the whole class name in")

    [ @public_flash, @owner_flash ].each do |partial|
      assert_match(/variant:\s*"alert-success"/, partial)
      assert_match(/variant:\s*"alert-error"/, partial)
    end
  end

  # The owner shell pins a navbar to the top edge below `lg`, and the drawer
  # button in it is the only route to the menu on a phone.
  test "the stack clears the owner's sticky navbar on small screens" do
    assert_match(/\.ledger-admin\s+\.toast-stack\s*\{[^}]*top:\s*4rem/m, @css,
      "a toast at y=0 covers the owner drawer button, which then looks " \
      "pressable and does nothing for as long as the toast is up")
    assert_match(
      /@media \(min-width: 64rem\)\s*\{\s*\.ledger-admin\s+\.toast-stack\s*\{[^}]*top:\s*0/m,
      @css,
      "above lg the navbar is hidden, so the offset must be given back")
  end

  test "the entrance animation is behind a reduced-motion guard" do
    guarded = @css.scan(/@media \(prefers-reduced-motion: [^)]+\)\s*\{.*?\n  \}/m)
      .select { |block| block.include?("toast") }

    refute_empty guarded,
      "a band that slides in must not slide for a reader who asked for less motion"
    assert_match(/@keyframes toast-in/, @css)
    assert_match(/animation:\s*toast-in\s+\d+ms/, guarded.join("\n"))
  end

  # A filled-forwards animation keeps its last keyframe applied at the
  # animation tier of the cascade, which outranks every normal author
  # declaration. `to { opacity: 1 }` would therefore beat `.toast-leaving`'s
  # `opacity: 0` for the life of the element, and the dismiss would read as a
  # cut rather than a fade — with nothing failing to say so.
  test "the entrance animation does not fill forwards over the leave state" do
    entrance = @css[/animation:\s*toast-in\s+[^;]*/]

    refute_nil entrance, "the entrance animation shorthand is gone"
    refute_match(/\b(forwards|both)\b/, entrance,
      "a forwards-filled entrance outranks .toast-leaving { opacity: 0 } and " \
      "kills the fade-out; use `backwards`")
  end

  test "the stack never reaches paper" do
    assert_match(/@media print\s*\{\s*\.toast-stack\s*\{\s*display:\s*none/m, @css,
      "the QR card sheets are cut out and stood on tables; a fixed overlay " \
      "stamped across them is a wasted print run")
  end


  test "the owner flash target exists whether or not there is a flash" do
    target = @owner_flash[/<div id="flash-messages">/]
    assert target, "owner/shared/_flash must render #flash-messages"

    before = @owner_flash[0...@owner_flash.index('<div id="flash-messages">')]
    refute_match(/<%\s*if\b/, before.gsub(/<%#.*?%>/m, ""),
      "owner/wine_list_items replaces #flash-messages by id from a Turbo " \
      "Stream; wrapping the target in a conditional silently drops the message"
    )
  end

  # Turbo caches a page as it leaves it and paints that snapshot instantly on
  # back/forward, before the fresh response lands. A flash baked into the
  # snapshot is a message the reader already dealt with, and it does not come
  # back quietly — the band animates in and arms a fresh six-second timer, so
  # it reads as something new having just happened.
  test "the stack is dropped from Turbo's cached snapshot" do
    [ [ @public_flash, "public" ], [ @owner_flash, "owner" ] ].each do |partial, name|
      assert_match(/<div class="toast-stack" data-turbo-temporary>/, partial,
        "#{name} flash: without this the toast replays on back/forward")
    end
  end

  # The wrapper is the Turbo Stream target, so unlike the stack it has to
  # survive into the snapshot — a stream that lands on a restored page with no
  # #flash-messages in it drops the message silently.
  test "the owner Turbo Stream target is not dropped from the snapshot" do
    target = @owner_flash[/<div id="flash-messages"[^>]*>/]

    refute_match(/data-turbo-temporary/, target,
      "#flash-messages is replaced by id from a Turbo Stream; drop it from " \
      "the cached snapshot and the stream has nothing to replace")
  end

  test "both surfaces float the same stack" do
    [ [ @public_flash, "public" ], [ @owner_flash, "owner" ] ].each do |partial, name|
      assert_match(/class="toast-stack"/, partial, "#{name} flash must use the shared stack")
      assert_match(%r{render "shared/flash_band"}, partial,
        "#{name} flash must render the shared band rather than its own copy of the markup")
    end
  end

  # The narrowing hook existed only to keep an in-flow banner from outrunning
  # the form it referred to. A floating stack has its own width.
  test "the dead flash_class plumbing is gone" do
    %w[
      app/views/shared/_flash.html.erb
      app/views/sessions/new.html.erb
      app/views/registrations/new.html.erb
    ].each do |view|
      refute_match(/flash_class/, Rails.root.join(view).read,
        "#{view}: content_for(:flash_class) no longer reaches anything")
    end
  end

  test "each band names its state in words and takes no focus" do
    assert_match(/role="alert"/, @band,
      "role=alert is a live region — it announces the band without moving focus into it")
    assert_match(/mono-label/, @band, "success and error must never rest on colour alone")
    assert_match(/icon icon_name/, @band, "each state carries its own icon")
  end

  test "the dismiss control is labelled and large enough to hit" do
    assert_match(/aria-label="<%= t\("shared\.flash_dismiss"\) %>"/, @band,
      "an icon-only button needs an accessible name, and it has to be translated")
    assert_match(/icon "x", class:/, @band,
      "rails_icons only recognises class: — css: renders and is silently discarded")

    dismiss = @css[/^\s*\.toast-dismiss\s*\{[^}]*\}/m]
    assert dismiss, ".toast-dismiss is missing from the stylesheet"
    assert_match(/min-height:\s*44px/, dismiss, "WCAG 2.5.5 puts the floor at 44px")
    assert_match(/min-width:\s*44px/, dismiss)
  end

  test "the dismiss copy is a shared key present in both locales" do
    %w[en it].each do |locale|
      yaml = YAML.load_file(Rails.root.join("config/locales/#{locale}.yml"))[locale]

      assert yaml.dig("shared", "flash_dismiss"),
        "#{locale}.yml: every flash band renders shared.flash_dismiss"
    end
  end


  test "the auto-dismiss delay is configurable from the partial" do
    assert_match(/static values = \{[^}]*timeout/m, @controller,
      "the delay is a Stimulus value so the partial, not the controller, decides it")
    assert_match(/data-flash-timeout-value=/, @band)
  end

  test "nothing auto-dismisses under test" do
    assert_equal 0, ApplicationHelper.instance_method(:flash_toast_timeout_ms).bind(
      Object.new.extend(ApplicationHelper)
    ).call,
      "a timer that fires mid-assertion turns every flash system test into a coin flip"
  end

  test "the timer is cleared when the band leaves the document" do
    assert_match(/disconnect\(\)\s*\{[^}]*clearTimers\(\)/m, @controller,
      "Turbo swaps pages without a reload; a live timer would fire against a " \
      "detached element, or outlive the page that set it")
    assert_match(/clearTimeout/, @controller)
  end
end
