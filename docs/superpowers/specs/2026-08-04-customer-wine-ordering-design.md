# Customer wine ordering — design

**Date:** 2026-08-04
**Branch:** `feat/customer-wine-ordering`

## Goal

Let a diner order wine from the menu they reach by scanning a QR code. The cart is
per restaurant, so a diner who visits two restaurants on the same device keeps two
independent carts. Ordering requires no account.

The owner side already exists: `Owner::OrdersController` lists orders and exposes
`approve!` / `cancel!`, and `Order#approve!` is what decrements stock. This work
builds only the customer half plus the small owner-view changes guest orders force.

## Decisions

| Question | Decision |
|---|---|
| Sign-in required to order? | No. Guest ordering, `orders.customer_id` becomes nullable. |
| Where does the cart live? | Session cookie, keyed by restaurant id. No cart tables. |
| After submit? | Order created as `pending`, diner redirected to a revisitable status page. |
| Ordering without a table? | Allowed. The owner chooses which QR to print; table is attached when known. |
| Bot defence | Honeypot + `rate_limit`. Turnstile deferred to its own PR. |

## What already exists

- `RestaurantTable` has `has_secure_token :token`; `/t/:table_token` resolves it.
- `MenusController#remember_table` already writes
  `session[:table_tokens] = {restaurant_id.to_s => token}` — a per-restaurant map.
  The cart deliberately mirrors this shape.
- A table is only attached to the session when it is `active`, so a retired printed
  QR degrades to a browse-only menu. Ordering inherits that behaviour.
- `Order`, `OrderItem`, `Order#calculate_total!`, `#approve!`, `#cancel!`.
- `QrSvgRenderer` and the owner-side QR printing views.
- `rate_limit` is already used in `Owner::AddressSuggestionsController` and
  `Owner::WineLookupsController`; a cache store is configured in every environment
  (`:memory_store` in dev/test, `:solid_cache_store` in production).

## Data model

One migration, all additive or widening — safe to run at Render build time.

```ruby
change_column_null :orders, :customer_id, true
add_column :orders, :public_token, :string
add_column :orders, :guest_name, :string
# backfill public_token for existing rows, then:
change_column_null :orders, :public_token, false
add_index :orders, :public_token, unique: true
```

Because `public_token` is `NOT NULL` and unique on every row, every order is
identifiable on its own; no additional check constraint is needed to guarantee that.

`Order` gains `has_secure_token :public_token` (24 chars, base58 — the same
unguessable-capability pattern as `RestaurantTable#token`), `belongs_to :customer,
optional: true`, and a `guest_name` length cap. Every customer-placed order gets a
`public_token` whether or not a user is signed in, so the status page has one
lookup path.

`guest_name` is optional and free text, shown to staff to help them deliver the
order. It is the only diner-supplied string persisted; it is length-capped and
HTML-escaped on render like any other user input.

## Cart

A plain object, not a table — following the `TableBulkGeneration` precedent.

**`app/models/cart.rb`** — `Cart.new(session:, restaurant:)`, reading and writing
`session[:carts][restaurant.id.to_s]`, an array of
`{"wine_id" => Integer, "glass_size_ml" => Integer, "quantity" => Integer}`.

API: `items`, `add(wine_id:, glass_size_ml:, quantity:)`, `update_quantity`,
`remove`, `clear`, `total_cents`, `empty?`, `item_count`, `dropped_items`.

**`app/models/cart_item.rb`** — a value object wrapping a `Wine`, a glass size and a
quantity, exposing `unit_price_cents`, `subtotal_cents`, `wine`.

Rules:

- **Prices are never written to the session.** They are read from the `Wine` on every
  render and again inside `PlaceOrder`. A tampered cookie therefore cannot set its
  own price. (The session cookie is signed anyway; this is defence in depth.)
- A wine must belong to the cart's restaurant. This is what prevents a crafted
  request from adding restaurant B's wine to restaurant A's cart.
- A wine must be `available?` and must have a price for the requested glass size.
- `glass_size_ml` must be one of `Wine::GLASS_SIZES`.
- Quantity is clamped to `1..MAX_QUANTITY_PER_ITEM` (20).
- At most `MAX_DISTINCT_ITEMS` (25) lines, keeping the cart well inside the 4KB
  cookie limit.
- Entries whose wine has been deleted or has gone unavailable since it was added are
  dropped on read and reported through `dropped_items`, so the view can tell the
  diner rather than silently changing their order.
- Adding a `(wine, glass_size)` pair already in the cart increments its quantity
  instead of appending a duplicate line.

All mutations write a **new** array back into the session rather than mutating in
place, per the project's immutability rule.

## Controllers and routes

Both controllers are public and sit inside the existing `scope "(:locale)"`.

```
GET    /menu/:restaurant_id/cart          carts#show
POST   /menu/:restaurant_id/cart/items    carts#add_item
PATCH  /menu/:restaurant_id/cart/items    carts#update_item
DELETE /menu/:restaurant_id/cart/items    carts#remove_item
DELETE /menu/:restaurant_id/cart          carts#destroy
POST   /menu/:restaurant_id/orders        orders#create
GET    /orders/:public_token              orders#show
```

`MenusController` currently owns restaurant-and-table resolution. That logic moves
to a `CustomerScoped` concern shared by `MenusController`, `CartsController` and
`OrdersController`: `set_restaurant` (`Restaurant.active.find`, 404 otherwise, so
inactive restaurants stay invisible) and `current_table` (reads
`session[:table_tokens]`, returns the table only when it is still active and still
belongs to this restaurant). This is a refactor of existing behaviour, not a change
to it — the existing `menus_controller_test.rb` coverage must keep passing untouched.

`OrdersController#create`:

- `rate_limit to: 5, within: 1.minute`, keyed by the session id falling back to the
  remote IP (`session.id` is nil until the session has been written, which is not
  guaranteed for a first request), responding with a flash and a redirect rather than
  a bare 429, since a diner may legitimately retry.
- Honeypot: a hidden, `aria-hidden`, off-screen field. When filled, respond with the
  normal success redirect but create nothing — a bot gets no signal.
- Strong params, integers coerced; no mass assignment of `status`, `total_amount_cents`,
  `restaurant_id`, `restaurant_table_id` or `customer_id`, all of which are set server-side.

`OrdersController#show` finds by `public_token` and 404s otherwise. It renders no
data beyond that order.

## PlaceOrder

`app/services/place_order.rb`, following the `QrSvgRenderer` service precedent.

`PlaceOrder.call(cart:, restaurant:, table:, customer:, guest_name:)` runs in a
transaction and:

1. Re-reads every cart line against live wine state and rejects the whole order if
   any wine has become unavailable, returning the offending items so the diner sees
   why.
2. Refuses an empty cart.
3. Creates the `Order` — `status: :pending`, `restaurant`, `restaurant_table` (nil
   when the session has no live table), `customer` (nil for guests), `guest_name`.
4. Creates one `OrderItem` per line, snapshotting `unit_price_cents` from the wine at
   this moment, so a later price change never rewrites a placed order.
5. Calls `calculate_total!`.
6. Clears that restaurant's cart from the session — and only that restaurant's.

It returns a result object exposing `success?`, `order` and `errors`.

**Stock is not decremented here.** `available_glasses` is only touched by the owner's
existing `Order#approve!`. Two diners can therefore both order the last glass; the
owner resolves it by approving one and cancelling the other. This is deliberate: it
avoids a checkout-time race and keeps the single existing stock-mutation path.

## Views

- `menus/_wine_row.html.erb` — an add button per priced glass size, rendered only when
  `wine.available?`. Otherwise the row stays exactly as it is today.
- A sticky bottom bar on the menu when the cart is non-empty: item count, total, link
  to the cart.
- `carts/show.html.erb` — lines with quantity steppers and remove, total, optional
  name field, honeypot, and the send button. Shows the table name when one is
  attached and says the order carries no table when not.
- `orders/show.html.erb` — status badge (pending / approved / cancelled / completed),
  items, total, table.
- Plain forms and Turbo Drive; no new Stimulus controllers, no Turbo Streams.
- daisyUI `wine` theme, reusing `.btn-wine`; mobile-first, WCAG 2.1 AA — every control
  is a real button or link with an accessible name, and status is conveyed by text as
  well as colour.
- Both `config/locales/en.yml` and `it.yml` updated. No user-visible string is
  hardcoded in a view.

## Owner-side changes

`app/views/owner/orders/index.html.erb:39` and `show.html.erb:8` both call
`order.customer.name`, which raises on a guest order. Both become a helper that
returns the customer name, else `guest_name`, else a translated "Guest".

## Testing

Unit — `test/models/cart_test.rb` (per-restaurant isolation, price never trusted from
session, cross-restaurant wine rejected, quantity clamping, item cap, dropped
unavailable items, merge on repeat add, immutable writes), `cart_item_test.rb`,
`test/services/place_order_test.rb` (price snapshot, empty cart, wine gone
unavailable mid-flight, only the one restaurant's cart cleared), and `order_test.rb`
extended for a nil customer.

Integration — `carts_controller_test.rb` and `orders_controller_test.rb`: guest and
signed-in ordering; with and without a table; retired table token attaches no table;
inactive restaurant 404s; cross-restaurant wine rejected; two restaurants' carts
independent in one session; honeypot creates nothing; rate limit trips; status page
by token; wrong token 404s; price change after add does not change the placed order.

System — `test/system/wine_ordering_test.rb`: scan a table QR, add two wines, adjust a
quantity, send, land on the status page; plus a second test proving two restaurants'
carts stay separate in one browser session.

Owner — `test/integration/owner/orders_controller_test.rb` extended so a guest order
renders in both the index and the show view.

## Out of scope

Turnstile (its own PR, covering sign-up too), live owner updates via Turbo Streams,
converting a guest order into an account, payments, order editing after submission,
and abandoned-cart analytics.
