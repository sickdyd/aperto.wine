# Reserve stock at order placement

## Context

Today `available_glasses` only moves in `Order#approve!`. That puts the stock
check minutes away from the only moment a diner is present to be told
anything, so an oversell is discovered by a server carrying a glass that
doesn't exist. Placement, meanwhile, checks availability but never quantity:
`Wine#available?` is only `active? && available_glasses.positive?`, so a wine
with one glass left accepts an order for twenty.

This moves the reservation to placement, under a row lock, so the check and
the audience share a moment. Approval becomes a workflow decision that no
longer mutates inventory. Cancelling releases the reservation.

`available_glasses` accordingly changes meaning from "on hand" to "not yet
spoken for".

## Global Constraints

- **Stock moves in exactly two places**: `PlaceOrder` reserves (decrement),
  `Order#cancel!` releases (increment). `Order#approve!` is stock-neutral.
- **The reservation check runs under `SELECT … FOR UPDATE`**, with wines
  locked in `id` order so two concurrent placements over overlapping wines
  cannot deadlock.
- **A shortfall aborts the whole placement.** No partial orders — this is the
  existing rule for `:items_unavailable` and it does not change.
- **Sold out stays a dropped line.** A wine at 0 glasses is already
  `available? == false` and already becomes a `Cart::DroppedItem`. The new
  "exceeds stock" state applies only when `0 < available_glasses < quantity`.
- **No auto-expiry of pending reservations.** A pending order holds its
  glasses until an owner approves or cancels it. Deliberate: no background
  job, no new column.
- **No owner-side UI change.** The wines index keeps its single
  `available_glasses` column.
- Both `en.yml` and `it.yml` must stay at key parity — `test/i18n_test.rb`
  fails the suite otherwise. Production runs `:it`.
- TDD throughout: failing test first. Unit + integration + system coverage.

## Task 1 — `Order` status guards and release on cancel

`app/models/order.rb`, `test/models/order_test.rb`.

- `#approve!` no longer decrements `available_glasses`. It keeps the
  bottle-opening behaviour (open a sealed bottle when none is open) and gains
  a guard: it does nothing and returns `false` unless the order is `pending?`.
- `#cancel!` releases the reservation — increments each item's wine by the
  item's quantity — when cancelling from `pending` **or** `approved`. Today it
  restores only from `approved`, which the owner UI cannot even reach (the
  buttons render only for `pending?`). It gains the same guard: no-op unless
  the order is `pending?` or `approved?`, so a second cancel cannot
  double-restore.
- A `completed` order never returns stock.

Existing tests that assert `approve!` decrements and that `cancel!` restores
only from `approved` are now wrong and must be rewritten, not deleted: the
new assertions are that `approve!` leaves stock untouched and that `cancel!`
from `pending` restores it.

New tests: approve twice only opens one bottle and never moves stock; cancel
twice restores once; cancel from `completed` restores nothing.

## Task 2 — `PlaceOrder` reserves under a lock

`app/services/place_order.rb`, `config/locales/{en,it}.yml`,
`test/services/place_order_test.rb`,
`test/integration/orders_controller_test.rb` (or wherever public order
placement is covered).

- Keep the existing pre-transaction `dropped_items` / `empty_cart` gates
  exactly as they are.
- Inside `build_order!`'s transaction, before creating anything: load the
  cart's wines with `Wine.where(id: ids).order(:id).lock`, and compare each
  cart line's `quantity` against the locked `available_glasses`.
- Any line short of stock aborts: roll the transaction back and return
  `failure(:insufficient_stock)`. No `Order` and no `OrderItem` rows survive.
- On success, decrement each wine's `available_glasses` by its line quantity
  inside the same transaction.
- Add the `:insufficient_stock` symbol to the `Result#error` documentation
  comment listing the exhaustive error set.
- `orders.errors.insufficient_stock` in both locale files. English:
  "Some items in your cart are no longer available in the quantity you asked
  for. Please review your cart before ordering." Italian to match.
  `OrdersController#create` already interpolates `result.error` into
  `t("orders.errors.#{...}")`, so it needs no change.

Tests: a shortfall creates no order and returns `:insufficient_stock`; a
successful placement decrements each wine by its line quantity; the
integration test asserts the redirect back to the cart carries the flash.
The existing `place_order_test.rb` assertion that stock is unchanged after
placement inverts.

## Task 3 — `Cart` and `CartItem` stock awareness

`app/models/cart.rb`, `app/models/cart_item.rb`,
`config/locales/{en,it}.yml`, `test/models/cart_test.rb`.

- `CartItem#exceeds_stock?` — `quantity > wine.available_glasses`.
- `Cart#orderable?` — `dropped_items.empty? && items.none?(&:exceeds_stock?)`.
  Note this is about the cart as a whole; `#empty?` and `#any_lines?` keep
  their current meanings.
- `Cart#add` returns `failure(:insufficient_stock)` when the resulting
  quantity for that line would exceed the wine's `available_glasses`. The
  check goes after the existing `:wine_unavailable` and `:price_unavailable`
  guards, so a sold-out wine still reports `:wine_unavailable`.
- `Cart#update_quantity` returns the same failure when the requested quantity
  exceeds stock. Quantity `<= 0` still removes the line.
- Document `:insufficient_stock` in the `Result` comment's exhaustive symbol
  list.
- `cart.errors.insufficient_stock` in both locales — English: "Only %{count}
  left of that wine." The `CartItemsController` flash path already maps cart
  error symbols onto `cart.errors.*`; check it and follow whatever it does
  for interpolation, adjusting the message to a non-interpolated string if
  that path cannot supply a count.

Tests: adding past stock fails; adding up to stock succeeds; incrementing an
existing line past stock fails; `update_quantity` past stock fails; a line
that was fine until stock dropped underneath it is reported by
`exceeds_stock?` and makes `orderable?` false; a sold-out wine still lands in
`dropped_items` rather than `exceeds_stock?`.

## Task 4 — Cart view surfaces the shortfall

`app/views/carts/show.html.erb`, `app/views/carts/_cart_item.html.erb`,
`config/locales/{en,it}.yml`, `test/views/…` if the project has cart view
tests, `test/system/…` for the customer cart flow.

- A warning banner distinct from the existing dropped-items alert, shown when
  any item `exceeds_stock?`. English: "One or more items exceed what's left
  — lower the quantity to order."
- On the offending line, an inline note naming the number left: "Only
  %{count} left — lower the quantity to order." The line keeps its normal
  treatment and its quantity stepper; it is **not** struck out like a dropped
  line.
- The submit form renders gated on `@cart.orderable?` rather than
  `items.any?`. When items exist but the cart is not orderable, the form is
  replaced by the banner and the lines, not by the empty state.
- Follow the design system in `PRODUCT.md` and `app/assets/tailwind/
  application.css`: no assembled-in-ERB Tailwind class names, reuse existing
  component classes rather than inventing near-duplicates, and check
  `docs/ASSETS.md` before reaching for an icon.
- The banner needs `role="alert"` like the dropped-items one; the inline note
  must be associated with its line for screen readers, not floating text.

Tests: a system test covering the diner lowering an over-stock line and then
successfully ordering, and one asserting the submit control is absent while a
line exceeds stock.
