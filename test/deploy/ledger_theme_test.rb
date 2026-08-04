require "test_helper"

# Guards the Sommelier's Ledger design contract. Every view in the app is
# restyled against the vocabulary declared in one stylesheet, so a token that
# quietly disappears — or a class name that gets renamed rather than restyled —
# breaks screens far from the edit. None of this is exercised by a request
# spec, hence the coverage.
class LedgerThemeTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/tailwind/application.css")
  PUBLIC_LAYOUT = Rails.root.join("app/views/layouts/application.html.erb")
  OWNER_LAYOUT = Rails.root.join("app/views/layouts/owner.html.erb")
  POUR_PARTIAL = Rails.root.join("app/views/shared/_pour.html.erb")

  # Everything after this comment banner in the stylesheet is deliberately
  # unlayered. See the banner itself for why.
  UNLAYERED_MARKER = "daisyUI reskins — deliberately UNLAYERED".freeze


  # Class names already spread across the views and the test suite. The ledger
  # restyles them; renaming any of them is a breaking change.
  PRESERVED_CLASSES = %w[
    btn-wine btn-wine-outline
    wine-dot wine-dot-red wine-dot-white wine-dot-rose wine-dot-sparkling wine-dot-dessert
    field field-label field-hint field-toggle
    form-section form-section-title form-actions
    address-suggestions address-suggestion address-suggestion-attribution
  ].freeze

  # The five-step oxblood ramp, three paper stocks plus the card sheet, the
  # inks, and the rule ramp. These are the vocabulary the area views build on.
  REQUIRED_TOKENS = %w[
    --color-ox-1 --color-ox-2 --color-ox-3 --color-ox-4 --color-ox-5
    --color-paper --color-stock --color-stock-pale --color-sheet
    --color-ink --color-ink-soft --color-quiet --color-on-deep
    --color-rule-hair --color-rule-fine --color-rule-medium --color-rule-heavy
    --color-leader
    --color-wine-red --color-wine-white --color-wine-rose
    --color-wine-sparkling --color-wine-dessert
    --font-display --font-body --font-mono
  ].freeze

  FONT_FAMILIES = [ "EB+Garamond", "Instrument+Serif", "JetBrains+Mono" ].freeze

  setup do
    @css = STYLESHEET.read
    @public_layout = PUBLIC_LAYOUT.read
    @owner_layout = OWNER_LAYOUT.read
  end

  test "daisyUI is rethemed rather than removed" do
    assert_match(/@plugin\s+"daisyui"/, @css,
      "the app's 47 views are built on daisyUI components; the ledger retunes the theme, it does not drop the plugin")
    assert_match(/@plugin\s+"daisyui\/theme"/, @css)
  end

  test "every daisyUI radius token is zeroed" do
    %w[--radius-selector --radius-field --radius-box].each do |token|
      assert_match(/#{Regexp.escape(token)}:\s*0\s*;/, @css,
        "#{token} must be 0 — the ledger has no corners")
    end
  end

  test "Tailwind's own radius scale is zeroed too" do
    %w[--radius-sm --radius-md --radius-lg --radius-xl --radius-2xl].each do |token|
      assert_match(/#{Regexp.escape(token)}:\s*0\s*;/, @css,
        "#{token} must be 0, or a stray rounded-lg reintroduces a corner")
    end
  end

  test "the ledger tokens are all declared" do
    REQUIRED_TOKENS.each do |token|
      assert_match(/#{Regexp.escape(token)}:/, @css, "missing design token #{token}")
    end
  end

  test "body type is at least 16px" do
    assert_match(/--text-body:\s*1\.125rem/, @css,
      "menus are read in dim restaurant light; body copy stays at 18px")
  end

  test "the load-bearing class names survive the restyle" do
    PRESERVED_CLASSES.each do |name|
      assert_match(/^\s*\.#{Regexp.escape(name)}[\s,{:]/, @css,
        ".#{name} is referenced by existing views or tests and must be restyled, not renamed")
    end
  end

  test "the three rule weights and the section break are available" do
    %w[rule-hair rule-fine rule-medium rule-heavy rule-section].each do |name|
      assert_match(/^\s*\.#{name}\s*\{/, @css, "missing rule class .#{name}")
    end
  end

  test "the leader-dot pattern is available and tabular" do
    assert_match(/^\s*\.leader\s*\{/, @css)
    assert_match(/border-bottom:\s*1px dotted var\(--color-leader\)/, @css,
      "the leader is a dotted filler, not a solid rule")
    assert_match(/\.leader-value\s*\{[^}]*tabular-nums/m, @css,
      "values a reader compares down a column must use tabular figures")
  end

  test "nothing in the ledger casts a shadow" do
    offenders = @css.scan(/(?:^|[\s"'])(?:drop-)?shadow-(?:sm|md|lg|xl|2xl|inner)\b/)
    assert_empty offenders, "the ledger builds depth from stock and overlap, never elevation"
    refute_match(/^\s*box-shadow:(?!\s*none)/, @css,
      "box-shadow is only ever allowed as `none`")
  end

  test "both layouts load the three ledger families and nothing else" do
    [ @public_layout, @owner_layout ].each do |layout|
      FONT_FAMILIES.each do |family|
        assert_includes layout, family, "layout must request #{family.tr('+', ' ')}"
      end
      refute_includes layout, "Cormorant", "the previous display face is retired"
      refute_includes layout, "Outfit", "the previous body face is retired"
    end
  end

  test "each layout paints the grain overlay exactly once" do
    [ @public_layout, @owner_layout ].each do |layout|
      assert_equal 1, layout.scan(/class="grain"/).size,
        "the grain is a single page-level overlay, not a per-section decoration"
    end
    assert_match(/\.grain\s*\{[^}]*pointer-events:\s*none/m, @css,
      "the grain sits over the whole page and must never swallow a click")
  end

  test "the owner shell is scoped to the quiet admin vocabulary" do
    assert_match(/<body class="ledger-admin/, @owner_layout,
      "the admin holds the same tokens quiet; the scope class is how it does that")
    assert_match(/^\s*\.ledger-admin\s*\{/, @css)
  end

  # We reskin these daisyUI components by their own class name, which makes
  # cascade placement — not specificity — the thing that decides who wins.
  #
  # daisyUI 5 emits its components into sublayers nested inside @layer
  # utilities; our vocabulary lives in @layer components. Layer order is
  # resolved BEFORE specificity, and utilities is declared after components, so
  # a .input rule written inside @layer components loses to daisyUI's .input no
  # matter how specific it is. Doubling the class does not rescue it — that was
  # tried, shipped, and was still dead.
  #
  # The fix is to keep these rules unlayered: unlayered declarations outrank
  # every layered one. This guard fails if any of them drifts back inside a
  # layer, which is silent breakage — the control still renders, just as a
  # stock daisyUI box.
  DAISY_COLLISIONS = %w[
    input select textarea checkbox radio toggle alert badge
  ].freeze

  test "daisyUI reskins are declared outside any cascade layer" do
    layered, unlayered = @css.split(UNLAYERED_MARKER, 2)

    assert unlayered, "the unlayered reskin section is missing from the stylesheet"

    DAISY_COLLISIONS.each do |name|
      assert_match(/^\.#{name}\.#{name}[,: {]/, unlayered,
        ".#{name} must be reskinned in the unlayered section or daisyUI wins")
      refute_match(/^\s+\.#{name}\.?#{name}?\s*[,{]/, layered,
        ".#{name} is back inside @layer components, where daisyUI's own rule " \
        "in @layer utilities will silently override it")
    end
  end

  test "the toggle's on state differs by fill, not only by hue" do
    assert_match(/^\.toggle\.toggle:checked\s*\{[^}]*background-color:\s*var\(--color-ox-2\)/m, @css,
      "at radius 0 both toggle states are plain squares; the on state must " \
      "invert figure and ground so it is readable without relying on colour")
    assert_match(/^\.toggle\.toggle\s*\{[^}]*background-color:\s*transparent/m, @css,
      "the off state is an outlined empty track")
  end


  # daisyUI ships a stepper as .steps/.step, drawing counter bubbles and a
  # connector bar through ::before/::after. Pseudo-elements cannot be
  # overridden away, so unlike the reskins above these could not be won — they
  # were renamed instead. Tailwind's `group` marker (for group-hover: and
  # friends) collides outright with a component class of the same name: while
  # .group carried ledger margin, every link using `group` for a hover variant
  # silently inherited it.
  RENAMED_AWAY_FROM_COLLISION = {
    "steps" => "ledger-steps",
    "step"  => "ledger-step",
    "group" => "wine-group"
  }.freeze

  test "classes that collide with daisyUI or Tailwind were renamed, not fought" do
    RENAMED_AWAY_FROM_COLLISION.each do |collides, renamed|
      assert_match(/\.#{renamed}[\s,{:]/, @css, "missing renamed class .#{renamed}")
      refute_match(/^\.?\s*\.#{collides}[\s,{:]/, @css,
        ".#{collides} collides with a vendor class of the same name and must " \
        "stay renamed to .#{renamed}")
    end
  end

  test "no view still uses a collided class name" do
    Dir[Rails.root.join("app/views/**/*.erb")].each do |view|
      body = File.read(view)
      refute_match(/class="[^"]*(?<![\w-])group(?![\w-])/, body,
        "#{view}: bare .group is Tailwind's group marker; use .wine-group")
      refute_match(/class="[^"]*(?<![\w-])steps?(?![\w-])/, body,
        "#{view}: .step/.steps is daisyUI's stepper; use .ledger-step/.ledger-steps")
    end
  end

  test "both layouts disable animation under system tests" do
    [ [ @public_layout, "public" ], [ @owner_layout, "owner" ] ].each do |layout, name|
      assert_match(/Rails\.env\.test\?/, layout,
        "#{name} layout must kill transitions in test or Capybara clicks mid-animation")
      assert_match(/transition-duration:\s*0s\s*!important/, layout)
    end
  end

  test "no design token name is both a colour and a size" do
    colours = @css.scan(/--color-([a-z0-9-]+):/).flatten.to_set
    sizes   = @css.scan(/--text-([a-z0-9-]+):/).flatten.reject { |n| n.end_with?("--line-height") }.to_set
    clash = colours & sizes
    assert_empty clash,
      "#{clash.to_a.join(', ')} exists as both --color-* and --text-*; the " \
      "Tailwind utility resolves to the colour and the size is unreachable"
  end


  test "flash bands fill their column rather than shrink-wrapping" do
    assert_match(/^\.alert\.alert\s*\{[^}]*width:\s*100%/m, @css,
      "daisyUI sets .alert to width: fit-content, which shrink-wraps a flash " \
      "band to its own text and beats a flex parent's align-items: stretch")
  end

  test "both layouts declare a charset" do
    [ [ @public_layout, "public" ], [ @owner_layout, "owner" ] ].each do |layout, name|
      assert_match(/<meta charset="utf-8">/, layout, "#{name} layout needs a charset")
    end
  end


  test "form controls clear the 44px interactive-target floor" do
    block = @css[/^\.input\.input,.*?\}/m]
    assert block, "the unlayered input reskin is missing"
    assert_match(/height:\s*auto/, block,
      "daisyUI's fixed height wins over min-height unless height goes to auto")
    assert_match(/min-height:\s*46px/, block,
      "daisyUI sizes controls to 40px, under the WCAG 2.5.5 44px floor")
    assert_match(/padding-inline:\s*0/, block,
      "a ruled field starts flush with its label, not inset by daisyUI's 12px")
  end


  # rails_icons only recognises `class:`. Anything else — notably `css:`, which
  # this app used everywhere — falls through to string_attributes and is emitted
  # as a literal, meaningless css="..." attribute while the icon keeps the
  # library default size. It renders, so nothing fails; the size and tint are
  # just silently dropped. Verified: icon("clock", css: "size-3") produced
  # <svg class="size-5" css="size-3">.
  test "icon calls pass class:, never css:" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].filter_map do |view|
      lines = File.readlines(view).each_with_index.select do |line, _|
        line.match?(/\bicon[( ]/) && line.include?("css:") && !line.include?("render")
      end
      "#{view}:#{lines.map { |_, i| i + 1 }.join(',')}" if lines.any?
    end
    assert_empty offenders,
      "icon(..., css:) is a silent no-op — the icon renders at the library " \
      "default and the requested size/tint is discarded. Use class:."
  end

  test "the pour is decorative, self-contained and animation lives in the stylesheet" do
    partial = POUR_PARTIAL.read

    assert_match(/aria-hidden="true"/, partial,
      "surrounding content carries the meaning; the plate itself says nothing")
    refute_match(/<img|src=|https?:/, partial,
      "the engraving is inline SVG — no asset, no external request")
    refute_match(/\sstyle="/, partial, "styling belongs in the stylesheet, not on the element")
    assert_match(/@media \(prefers-reduced-motion: no-preference\)/, @css)
    assert_match(/\.pour-plate\s*\{\s*@apply/, @css)
  end
end
