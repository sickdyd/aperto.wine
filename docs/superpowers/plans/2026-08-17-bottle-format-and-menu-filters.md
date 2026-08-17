# Plan: bottle serving, wine character data, and menu filters

Branch: `feat/bottle-format-and-menu-filters`

## Why

Competitor research (Winevizer, Uncorkd, BinWise/SproutQR, ShareVino, Incentient
SmartCellar) found three gaps in aperto.wine's menu, all confirmed against the
code:

1. **The menu is glass-only.** `wines.price_bottle_cents` is captured in the
   owner form and printed in the owner index, but it never reaches the public
   menu, and `order_items.glass_size_ml` is `NOT NULL` — a bottle cannot be
   ordered or even seen. Every competitor is bottle-first.
2. **Half the `wines` table is dormant.** `aromas`, `food_pairings`, `acidity`,
   `tannins`, `sweetness`, `body`, `abv`, `style`, `short_description`,
   `organic`, `vegan`, `natural_wine`, `biodynamic` are validated on the model
   (and `food_pairings` is populated by `WineReferences::Importer`) but appear
   in neither the owner form nor the menu.
3. **No filters.** The menu has a substring search only. Competitors all offer
   browse-by-colour/region/grape/price.

## Global Constraints

These bind every task. A reviewer checks the diff against them.

- **Brand.** `PRODUCT.md` is authoritative. Zero border radius, no drop
  shadows, no display type in the admin. Rules (hairline/medium/heavy) and
  leader dots replace boxes. Oxblood is structure; black ink is body copy.
- **daisyUI cascade layers.** daisyUI 5 emits into sublayers of
  `@layer utilities`, which is declared *after* `components`. A `.input`-style
  override inside `@layer components` loses. The daisyUI reskins near the
  bottom of `app/assets/tailwind/application.css` are deliberately unlayered —
  do not move them. New ledger vocabulary goes in `@layer components` under a
  name daisyUI does not use.
- **No ERB-assembled Tailwind class names.** A class name built by string
  interpolation in ERB gets no CSS rule at all, silently. Write full literal
  class names and branch with `if`/`case`.
- **Locale parity.** Every new key lands in BOTH `config/locales/en.yml` and
  `config/locales/it.yml`. `test/i18n_test.rb` fails the suite on a missing or
  unused key or an inconsistent interpolation. `config.i18n.fallbacks = true`
  means a missing `en` key silently serves Italian — parity is the guard.
- **Immutability.** `Cart` and `OrderHistory` assign a new structure rather
  than mutating in place. Keep that. Cart reads must stay side-effect free.
- **Price trust.** Prices are never written to the session. `CartItem` always
  re-reads the live `Wine`. Preserve this for bottles.
- **Publication boundary.** A wine is orderable only if it sits on at least one
  of the restaurant's **active** `WineList`s (`Cart#published_wines`). Bottles
  are subject to the identical boundary. `:wine_not_found` must keep conflating
  "unpublished" with "does not exist".
- **Accessibility.** WCAG 2.1 AA: ≥4.5:1 contrast, 44×44 CSS px tap targets
  (`min-h-11 min-w-11`), label/input association, visible focus, reduced motion
  respected. Every new control carries an accessible name that includes the
  wine (the existing add buttons set the precedent: "Add Barolo, 125 ml").
- **Tests.** Unit + integration + system for each task. No network in tests
  (WebMock, `allow_localhost: true`). Do not create a class name in
  `test/models/` that already exists in `test/integration/` — the suite fails
  to boot. `test/system/` is exempt.
- **Migrations are additive only in this branch.** Render runs `db:migrate` as
  `preDeployCommand`, so a column drop must ship in a later deploy than the
  code that stops using it. Nothing here drops a column.
- **Rubocop** is rails-omakase. Run `bin/rubocop` before committing.

---

## Task 1 — `serving` on the domain model

Introduce an explicit serving format so a wine can be ordered by the bottle as
well as by the glass.

### Why explicit and not `glass_size_ml IS NULL`

`CartsController#integer_param` coerces a missing, blank, or non-numeric param
to `nil`. If `nil` meant "bottle", a malformed request would silently become a
bottle order. The serving must be its own validated value so a bad param fails
closed as `:invalid_serving`.

### Migration

One migration, `db/migrate/*_add_serving_to_order_items.rb`:

- Add `order_items.serving`, `:integer`, `default: 0`, `null: false`.
- Change `order_items.glass_size_ml` to `null: true`.
- Add a check constraint named `order_items_serving_glass_size`:
  `(serving = 0 AND glass_size_ml IS NOT NULL) OR (serving = 1 AND glass_size_ml IS NULL)`

  Follow the `wines` table's existing `t.check_constraint` precedent for
  naming and style.

Both changes are relaxing or additive, so they are safe in a single deploy.
`add_column` with a default on Postgres 11+ does not rewrite the table.

Regenerate `db/schema.rb` against a **scratch database**, never the shared
development database. Confirm the committed `schema.rb` diff contains only this
migration's changes and the new `schema_migrations` version.

### `OrderItem`

```ruby
enum :serving, { glass: 0, bottle: 1 }
```

Replace the unconditional `glass_size_ml` inclusion validation with:

- when `glass?` — `glass_size_ml` must be in `Wine::GLASS_SIZES`
- when `bottle?` — `glass_size_ml` must be `nil`

Keep the `quantity` and `unit_price_cents` validations as they are.

`OrderItem` gains no serving-aware price logic — `unit_price_cents` is already a
snapshot and stays so.

### `Wine`

Add:

- `SERVINGS = %w[glass bottle].freeze`
- `glasses_available?` — `active? && available_glasses.positive?`
  (this is today's `available?` body, renamed for what it actually means)
- `bottle_available?` — `active? && price_bottle_cents.to_i.positive?`

  There is no bottle stock column; a positive bottle price is the owner's
  signal that whole bottles are sold. A wine with zero glasses left but a
  bottle price is bottle-orderable — that is the intended new behaviour and
  the point of the feature.
- `price_for(serving:, glass_size_ml: nil)` — dispatches to
  `price_bottle_cents` for `"bottle"`, `price_for_glass` for `"glass"`, and
  returns `nil` for an unrecognised serving.
- `available_for?(serving:, glass_size_ml: nil)` — `bottle_available?` for
  `"bottle"`, `glasses_available?` for `"glass"`, `false` otherwise.

Redefine `available?` as `glasses_available? || bottle_available?` — "orderable
in some form". This is what the menu's sold-out tag means.

**Every existing caller of `Wine#available?` must be re-examined**, because its
meaning widens. `Cart#drop_reason` in particular must stop using it and use
`available_for?` instead — otherwise a glass line for a wine with zero glasses
but a bottle price would pass the availability check and then be priced from a
`price_75ml_cents` that is still set, ordering a glass the restaurant cannot
pour. Grep for `available?` across `app/` and `test/` and fix each site
deliberately. `Wine#suggested_glasses` and `price_for_glass` stay unchanged.

### Tests

`test/models/wine_test.rb` and `test/models/order_item_test.rb`:

- `glasses_available?` / `bottle_available?` / `available?` across the matrix:
  inactive; active with glasses and no bottle price; active with a bottle price
  and zero glasses; active with both; active with neither; bottle price of `0`
  (must read as not available — zero and nil mean the same thing here, matching
  how `Cart#positive_price?` already treats glass prices).
- `price_for` for both servings, an unknown serving, and a nil glass size.
- `available_for?` across the same matrix.
- `OrderItem` validity: glass with a valid size; glass with a size not in
  `GLASS_SIZES`; glass with `nil` size; bottle with `nil` size; bottle with a
  size present.
- One test that the database check constraint actually rejects an inconsistent
  row inserted around the model validations (`update_column` or raw SQL, expect
  `ActiveRecord::StatementInvalid`).

---

## Task 2 — `serving` through `Cart`, `CartItem`, and `PlaceOrder`

Depends on Task 1.

### Session shape

A cart line becomes:

```ruby
{ "wine_id" => 7, "serving" => "glass", "glass_size_ml" => 125, "quantity" => 2 }
{ "wine_id" => 9, "serving" => "bottle", "glass_size_ml" => nil, "quantity" => 1 }
```

Line identity is the triple `(wine_id, serving, glass_size_ml)`, so the same
wine can sit in the cart as a bottle and as two different pours at once.

**Backward compatibility is required.** Live diners have `session[:carts]`
lines with no `"serving"` key. A line missing the key reads as `"glass"`. Do
this in one private normaliser used by every read path — never by rewriting the
session, because `Cart` reads must stay side-effect free (`#items` explicitly
never writes). Update the class's session-shape comment to document both the
new shape and the legacy fallback.

### `Cart`

- `add(wine_id:, serving:, glass_size_ml: nil, quantity: 1)`
- `update_quantity(wine_id:, serving:, glass_size_ml:, quantity:)`
- `remove(wine_id:, serving:, glass_size_ml:)`

Validation order in `#add`, failing closed:

1. `serving` must be in `Wine::SERVINGS` → else `:invalid_serving`
2. for `"glass"`, `glass_size_ml` must be in `Wine::GLASS_SIZES` → else
   `:invalid_glass_size`; for `"bottle"`, coerce `glass_size_ml` to `nil`
   regardless of what was passed
3. `published_wines.find_by(id:)` → else `:wine_not_found`
4. `wine.available_for?(serving:, glass_size_ml:)` → else `:wine_unavailable`
5. positive `wine.price_for(serving:, glass_size_ml:)` → else
   `:price_unavailable`

Add `:invalid_serving` to the documented `Result` error symbol set in the class
comment, and extend `DroppedItem` with `serving`. `#drop_reason` takes the
serving and uses `available_for?` and `price_for` (see Task 1 — it must not use
the widened `available?`). `MAX_QUANTITY_PER_ITEM` and `MAX_DISTINCT_ITEMS` keep
their current values and meanings; a bottle line is one distinct item like any
other.

Keep `stored_lines`/`persist`/`replace_line`/`remove_line` assigning new
structures. `line_index` matches on the triple, comparing the normalised
serving so a legacy keyless line is still found by a `"glass"` lookup.

### `CartItem`

Gains `serving`. `unit_price_cents` becomes
`wine.price_for(serving: serving, glass_size_ml: glass_size_ml)` — still always
read from the live wine, never the session.

### `PlaceOrder`

`create_order_item!` passes `serving:` through to `OrderItem`. Extend the
`:items_unavailable` doc comment to mention a bottle losing its price. Nothing
else about the abort-the-whole-placement rule changes.

### `CartsController`

Read a `serving` param as a raw string (do **not** put it through
`integer_param`) and pass it to `Cart` unvalidated — `Cart` owns the validation
and returns `:invalid_serving`. `glass_size_ml` keeps going through
`integer_param`.

Add `cart.errors.invalid_serving` to both locale files.

### Tests

- `test/models/cart_test.rb`: add/update/remove for bottles; a bottle and two
  pours of the same wine coexisting as three lines; `:invalid_serving` for a
  missing, blank, and bogus serving; a bottle add with a stray
  `glass_size_ml` still stored as `nil`; `:price_unavailable` when
  `price_bottle_cents` is nil and when it is `0`; `:wine_unavailable` for a
  bottle on an inactive wine; **a glass line for a wine with zero glasses but a
  positive bottle price is dropped as `:wine_unavailable`** (the regression
  Task 1's note describes); a legacy line with no `"serving"` key reads as a
  glass, is found by `line_index`, and is not rewritten into the session by a
  read.
- `test/models/place_order_test.rb`: a mixed bottle+glass cart produces
  `OrderItem`s with the right `serving` and snapshotted prices; a bottle that
  lost its price aborts the whole placement.
- `test/integration/`: POST an add for a bottle; POST an add with a bad serving
  and assert the flash and that nothing entered the cart.

---

## Task 3 — the menu and the owner form surface the data

Depends on Tasks 1 and 2.

### `app/views/menus/_wine_row.html.erb`

The row keeps its shape: colour dot, name, leader dots, right-aligned prices.

- Build the price list from the servings actually offered — the bottle first (a
  printed card lists the bottle price first), then the priced pours in
  ascending size order. The bottle's size label is the wine's own
  `bottle_size_ml` rendered as a bottle label (e.g. `750 ml` for a standard
  bottle) rather than the word "bottle" alone; use a locale key so both
  languages read naturally. Reuse the existing `.price-grid` /
  `.price-size` / `.price-amount` vocabulary — do not invent a second price
  treatment.
- One add control per offered serving, in the same order, in the existing
  indented row. `aria-label` must name the wine and the serving.
- The sold-out tag now keys off `Wine#available?` (widened in Task 1), so a
  wine with bottles but no glasses is no longer struck through — it offers the
  bottle only. A wine with neither still shows the tag.
- Render, only when present, in this order beneath the existing meta line:
  - `short_description` — if present it replaces `description` as the row's
    note; `description` is the longer copy and stays the fallback.
  - certifications: `organic`, `natural_wine`, `vegan`, `biodynamic` as small
    mono labels. Literal class names only.
  - `abv` as `12.5% vol` via a locale key.
  - the tasting axes `body`, `tannins`, `acidity`, `sweetness` — only the ones
    that are non-nil. Render each as a label plus a 0–5 reading in the
    ledger idiom: leader dots to a filled/unfilled pip run, not a progress
    bar (no radius, no shadow, no colour fill beyond the oxblood ramp). Each
    needs a text equivalent for screen readers (e.g. "Body 4 of 5") — do not
    convey the value by shape alone.
  - `food_pairings` as a comma-joined line prefixed by a mono label.
  - `aromas` likewise.
  - `style` if present, as part of the meta line rather than its own row.
- Extend `data-search-terms` with `style`, `food_pairings`, and `aromas` so the
  existing substring search reaches them.
- `label_image` / `image_url` are **out of scope** — layout for label
  photography is its own design problem. Do not render them.

### `app/views/owner/wines/_form.html.erb` and `Owner::WinesController`

Add a fourth `fieldset.form-section` after "availability", legend from a new
locale key (character / tasting):

- `abv` — number field, step `0.1`, min 0, max 100
- `style` and `short_description` — text fields
- the four tasting axes — number fields, min 0, max 5, step 1
- the four certifications — `check_box` with the same `toggle toggle-primary`
  treatment `active` already uses
- `aromas` and `food_pairings` — Postgres string arrays. Present each as one
  comma-separated text field. Add a model-level writer pair (e.g.
  `aromas_list` / `aromas_list=`) that splits on commas, strips, and drops
  blanks, so the form never hands a raw string to an array column. Permit the
  `_list` attributes, not the arrays themselves — permitting an array attribute
  from a form is how mass-assignment surprises happen.

Extend `wine_params` accordingly. Follow the existing `field_error_attributes`
/ `field_errors` pattern on every new field. No display type, no illustration —
this is the quiet admin vocabulary.

### CSS

Add the new vocabulary to `@layer components` in
`app/assets/tailwind/application.css` under names daisyUI does not use
(`.wine-axis`, `.wine-axis-pips`, `.wine-cert`, `.wine-pairings`, …). Rebuild
with `bin/rails tailwindcss:build` and commit
`app/assets/builds/tailwind.css`.

### Locales

New keys in both `en.yml` and `it.yml`: the bottle price label, the abv format,
the four axis labels, the four certification labels, the pairings and aromas
labels, the owner fieldset legend, and every new owner field label and hint.
Italian is the production locale — write real Italian, not a machine gloss of
the English.

### Tests

- `test/integration/` (or the existing menu test file): the menu shows a bottle
  price and a bottle add control; a wine with bottles but no glasses renders
  orderable rather than sold out; certifications, axes, pairings, and aromas
  render when set and are absent from the markup when not.
- `test/integration/owner/`: the new fields round-trip through create and
  update; `aromas_list=` splits, strips, and drops blanks; a wine with no
  aromas submits an empty field without error.
- `test/models/wine_test.rb`: the `_list` writers and readers, including
  whitespace-only input and a single value with no comma.
- `test/system/`: a diner adds a bottle to the cart from the menu and sees it
  in the cart and on the placed order.

---

## Task 4 — menu filter chips

Depends on Task 3.

Extend the existing client-side filter rather than adding an endpoint. The menu
already renders every wine, `list_filter_controller.js` already hides items and
empty groups, and a server round-trip per filter tap would be slower and lose
the diner's scroll position.

### `app/javascript/controllers/list_filter_controller.js`

The controller is **shared** by the owner wines index, the list-builder
"Available wines" column, and the owner wine lists index. Every change must be
backward compatible: a page with no facet controls must behave exactly as it
does today.

- Keep the `input`/`item`/`group`/`empty` targets and the substring behaviour.
- Add an optional `facet` target: a control carrying `data-facet-name` and
  `data-facet-value`. An item matches when, for every facet name with an active
  selection, the item's `data-facet-<name>` list contains one of the selected
  values. Facets AND across names, OR within a name.
- Read item facet values from `data-facet-*` attributes, space- or
  pipe-separated. Never mutate item datasets — toggle visibility only, as the
  controller already documents.
- Debounce stays on the text input only; a chip tap applies immediately.
- Chips are `aria-pressed` toggle buttons, keyboard reachable, 44×44 minimum.
- Add a "clear all" control that resets the text input and every chip, shown
  only while something is active.

### The chips

Rendered in `menus/show.html.erb` between the search field and the section
nav, from the wines actually on the rendered lists — never a hardcoded list,
and a facet with fewer than two distinct values does not render at all (a chip
row where every chip matches everything is noise).

- **Colour** — from `Wine.colors`, restricted to colours present.
- **Serving** — "by the glass" / "by the bottle", from what the wines offer.
- **Certification** — organic / natural / vegan / biodynamic, only those
  present.
- **Price band** — computed from the wines present. Derive three bands from the
  rendered set's own price distribution (e.g. tertiles of the lowest offered
  price per wine) rather than hardcoding currency thresholds, and label them
  with the actual boundary amounts via a locale key. A set with fewer than
  three distinctly-priced wines renders no price facet.
- **Region** and **grape** are deliberately excluded: on a real list they run
  to dozens of values and the substring search already reaches both. Note this
  in the view comment so the omission reads as a decision.

Put the facet extraction in a helper (`app/helpers/`), not the view, and unit
test it. Keep the helper returning plain data structures the view renders.

### Tests

- `test/helpers/`: facet extraction — colours present, servings offered,
  certifications present, price banding including the fewer-than-three case and
  a set where every wine costs the same.
- `test/system/`: tapping a colour chip hides other colours; two chips in one
  facet OR together; chips in different facets AND together; a chip plus a
  search term compose; "clear all" restores everything; the empty-state message
  appears when a combination matches nothing.
- One system or integration test asserting the owner wines index still filters
  by text with no facet controls present (the shared-controller regression).
