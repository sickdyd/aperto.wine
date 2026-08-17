# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

aperto.wine is a Rails 8.1 app that turns a restaurant's wine cellar into a QR-accessible digital wine list. Two audiences, two very different surfaces:

- **Diners** scan a per-table QR, browse the menu on a phone, build a cart, and place an order — all **unauthenticated**.
- **Restaurant owners** manage restaurants, wines, wine lists, tables/QRs, and incoming orders from the `Owner::` admin area.

`PRODUCT.md` holds the product brief and the "Sommelier's Ledger" brand/design direction (print typography, oxblood ramp, zero radius, no shadows). Read it before touching UI. `docs/ASSETS.md` is the reference for icons/SVGs — check it before hunting for an asset. `docs/superpowers/{specs,plans}/` holds per-feature design docs.

## Commands

```sh
bin/setup                     # bundle, db:prepare, then starts the dev server
bin/dev                       # rails server + tailwindcss:watch (Procfile.dev), PORT defaults to 4010
bin/ci                        # full local CI chain (setup, rubocop, audits, tests, seed replant)

bin/test                      # unit + integration, serialized across worktrees
bin/test --system             # headless Chrome via Selenium — separate job in CI, not part of `test`
bin/test --all                # both suites under one lock — the pre-PR gate
bin/rails test test/models/cart_test.rb            # one file
bin/rails test test/models/cart_test.rb:42         # one test by line
bin/rails test -n "/pattern/"                      # by name

bin/rubocop                   # rails-omakase style
bin/brakeman --no-pager
bin/bundler-audit             # no --update (see lefthook.yml for why)
bin/importmap audit
npm audit --audit-level=moderate

bin/rails tailwindcss:build   # rebuild app/assets/builds/tailwind.css after CSS changes
bin/rails generate rails_icons:sync --library=phosphor --force   # restore gitignored icon SVGs
bin/rails wine_references:import[path/to.csv]                    # X-Wines catalogue import
bin/rails db:seed             # loads db/seeds/demo.rb in development (demo owner/admin, password "password")
```

Git hooks are managed by lefthook (`bundle exec lefthook install`): lint + security scans on commit, `bin/test` on push. CI (`.github/workflows/ci.yml`) additionally builds the production Docker image and runs system tests.

### Testing this repo from several worktrees

Every worktree resolves to the same Postgres and the same test databases, so two
full suites running at once corrupt each other's fixtures *and* oversubscribe the
machine — enough to make system tests fail on timing instead of on real
regressions. So:

- Run **whole** suites through `bin/test`, never `bin/rails test` directly. It
  takes a repo-wide lock, so a second caller queues for ~45s instead of racing.
- While iterating, run the **targeted** file or line (`bin/rails test <path>`) —
  cheap, unlocked, and what you want in a red/green loop.
- Run `bin/test --all` **once** before opening the PR. Re-running a green suite
  to see if it is still green just burns cores other sessions need.

## Architecture

### Request pipeline

`ApplicationController` does three things beyond the Rails defaults:

1. **Site-wide HTTP basic auth gate** — active only when `HTTP_AUTH_USER` is set (staging/pre-launch). Unset the env var to open the site, no deploy needed.
2. **Locale negotiation** (`around_action :switch_locale`) — priority is explicit `:locale` param → session override → `Accept-Language` (q-value ranked, RFC 9110) → `I18n.default_locale`. Everything user-controlled passes through `#supported_locale` first, because `I18n.with_locale` raises a 500 on an unknown locale. A locale that merely matches what the browser negotiated is *not* persisted.
3. `default_url_options` prefixes URLs with the locale only when it isn't the default — hence the `scope "(:locale)"` wrapper around every route.

Authentication is hand-rolled (`app/controllers/concerns/authentication.rb`): `has_secure_password`, `session[:user_id]`, `current_user`, `require_role!`. Roles are a `User#role` enum (`customer`/`owner`/`admin`). `Owner::BaseController` enforces `authenticate_user!` + owner/admin role and uses the `owner` layout.

### The customer side (unauthenticated)

`CustomerScoped` is the shared resolver for public endpoints. Its callbacks are **opt-in per action** — never declare them blanket-style, because `OrdersController#show` resolves an order by `public_token` alone and needs no restaurant.

- Restaurants resolve through `Restaurant.active` so an inactive restaurant 404s however it's addressed.
- A `/t/:table_token` visit remembers the table in `session[:table_tokens][restaurant_id]`, so a later request carrying only a restaurant id is still attributed to that table. A retired or reassigned token must never surface a stale table — `#current_table` re-validates active + ownership on every read.

Two non-ActiveRecord "models" carry customer state (both live in `app/models/` alongside `TableBulkGeneration`, both keyed by `restaurant_id.to_s`, both **assign a new structure rather than mutating in place**):

- **`Cart`** — session-backed, no table, no `carts` row ever. Prices are never written to the session; `Cart#items` re-reads the live `Wine` price so a tampered cookie can't dictate a price. Lines whose wine vanished/went unavailable/lost its price are reported as `dropped_items` rather than silently disappearing. Reads never rewrite the session. `#over_stock_wine_ids` answers stock **per wine, not per line** — two glass sizes of one wine draw from one pool — and `#orderable?` folds it together with `dropped_items` into the single question the cart view asks before offering a submit control. Both are a courtesy, not the enforcement: they read unlocked rows, so `PlaceOrder` re-checks everything under a lock regardless.
- **`OrderHistory`** — signed 24-hour cookie of order `public_token`s, so a device sees the orders it placed. Signed, not encrypted (the tokens are already in the confirmation URL). Parses defensively: anything malformed yields `[]`, never an exception. Resolution is scoped through `restaurant.orders` — *that scoping is the isolation guarantee*.

**The publication boundary**: a wine is orderable only if it sits on at least one of the restaurant's **active** `WineList`s (`Cart#published_wines`, mirroring `MenusController#show`). A wine on no list, or only on unpublished ones, must be as unreachable to the cart as it is to the menu. `:wine_not_found` deliberately doesn't distinguish "unpublished" from "doesn't exist" — the difference would leak the owner's choices.

**`PlaceOrder`** (`app/services/`) turns a cart into an `Order` in one transaction. Any line that fails the live re-check aborts the *whole* placement — shipping the survivors would serve a different order than the one the diner built.

**Stock is reserved at placement, not at approval.** `wines.available_glasses` therefore means "not yet spoken for", not "on hand": a pending order is already holding its glasses. `PlaceOrder` locks the cart's wines with `restaurant.wines.where(id: ...).order(:id).lock` inside the transaction — ascending id, so two placements over overlapping wines can't deadlock — accumulates the required quantity per wine across every cart line, and decrements only after the whole cart clears. This is the only check that counts; the cart's own guard runs on unlocked rows.

Two consequences worth holding onto:

- **`orders.stock_reserved`** exists because the two generations of order disagree about what a status implies. An order placed under the old code and still pending never took a decrement, so an unconditional release on cancel would *invent* glasses. `PlaceOrder` stamps the flag inside the reservation's own transaction; `Order#cancel!` releases only when it is set and clears it in the same UPDATE, so a double release is structurally impossible. `#approve!` and `#cancel!` both `lock!` the order row *before* reading their status guard — the in-memory attribute was loaded before the transaction opened, and trusting it let two staff tabs both run the body.
- **Placement requires a scanned table** (`:table_required`). The surface is unauthenticated and the menu is reachable from a bare slug URL, so without it one visitor could reserve an entire cellar from anywhere and only an owner cancelling each order would give it back. `CustomerScoped#current_table` is the resolver, and a retired token resolves to nothing — so it is refused exactly like never having scanned. The cart page withholds the submit control and says why (`cart.no_table_context`) rather than offering a button that can only fail.

On the owner's side, `wines.lock_version` guards the same counter from the other direction: the wine form edits `available_glasses` as an absolute number seeded when the page rendered, so a form left open while diners order would otherwise write the old figure back and resurrect reserved glasses. `Owner::WinesController#update` turns the resulting `StaleObjectError` into a 409 re-render. The `wines_available_glasses_non_negative` check constraint backs the model validation, which `decrement!` bypasses entirely (`update_counters` skips validations) — it is deliberately **not** rescued into a business failure, because the lock makes that state unreachable and masking it would hide data corruption.

### Live order notifications (owner side)

Action Cable is deliberately **not** loaded (see the commented railtie in `config/application.rb`). New orders reach the owner by polling instead: every owner page rendered inside a restaurant mounts `order_notifications_controller.js`, which asks `Owner::OrdersController#notifications` every 15s (1s under test — `order_notifications_poll_interval_ms`) and hands the answer to `Turbo.renderStreamMessage`.

The browser holds the state, not the server. It sends back the window of order ids it was last given (`known`, echoed in the `X-Order-Window` response header) plus the pending tally it is currently showing (`count`, read off the badge's `data-pending-count`); the server answers `204 No Content` when neither has moved. Both params are untrusted and used for nothing but comparison. `Order.notification_window` is the window on both sides — its `created_at DESC, id DESC` ordering is load-bearing, because an order free to drop out of the window and come back is an order announced twice, and `index_orders_on_restaurant_id_and_recency` exists solely so the app's most frequent query never sorts a restaurant's whole history.

Consequences elsewhere: `owner/shared/_flash` now renders its `.toast-stack` **unconditionally** (it is the append target for arriving orders, and a stream with no target is dropped silently), and the pending badge is rendered twice per page — sidebar and mobile top bar, ids in `Owner::OrdersHelper::BADGE_IDS` — because the sidebar is behind a drawer on a phone.

### Services

Plain objects with a single `.call`: `PlaceOrder`, `QrSvgRenderer`, `Geocoding`, `WineReferences::{Importer,Lookup,PythonList}`. `WineReference` is a read-only global catalogue (public-domain X-Wines, CC0) powering the owner's wine type-ahead — it belongs to no restaurant. Address autocomplete proxies Photon (OpenStreetMap) via `Owner::AddressSuggestionsController`; `Restaurant` geocodes as a best-effort `after_validation` fallback that never blocks a save.

### Frontend

Hotwire (Turbo + Stimulus via importmap) — no build step for JS. Tailwind 4 + daisyUI 5, compiled by `tailwindcss-rails` into `app/assets/builds/tailwind.css`. Icons come from the `rails_icons` gem (Phosphor).

`app/assets/tailwind/application.css` (~1600 lines) is the whole design system: a daisyUI theme block hands daisyUI the ledger palette, `@theme` exposes tokens as utilities, and `@layer components` adds the ledger vocabulary daisyUI can't express.

## Traps that have bitten this codebase

- **daisyUI cascade layers.** daisyUI 5 emits component CSS into sublayers of `@layer utilities`, which is declared *after* `components`. Layer order beats specificity, so a `.input` rule inside `@layer components` loses to daisyUI's — doubling the class does not help. The daisyUI reskins near the bottom of `application.css` are **deliberately unlayered**; moving one back into `@layer components` silently kills it. `.steps`/`.step`/`.group` were renamed (`.ledger-steps`, `.ledger-step`, `.wine-group`) because overriding them was impossible.
- **Tailwind class names assembled in ERB get no CSS rule at all**, silently. Write full literal class names.
- **`app/assets/svg/icons` is gitignored.** A fresh clone or worktree has no icons and tests fail with "Icon not found" until you run the `rails_icons:sync` generator. CI and `bin/render-build.sh` both sync it explicitly.
- **Locale drift.** `test/i18n_test.rb` fails the suite on any key missing from `en.yml` or `it.yml`, on inconsistent interpolations, and on unused keys (see `config/i18n-tasks.yml` for the ignore list). Production runs `:it`; the **test env runs `:en`** with `raise_on_missing_translations = true`. `config.i18n.fallbacks = true` means `en` falls back to `it`, so a missing English key leaks Italian rather than erroring — keep both files at parity.
- **Duplicate test class names.** The same class name in `test/models/` and `test/integration/` makes the whole suite fail to boot. `test/system/` is exempt.
- **No network in tests.** WebMock is on with `allow_localhost: true`; `test_helper.rb` stubs Photon to return nothing by default. Declare `stub_photon(...)` in tests that need suggestions.
- **System tests are retried twice** (`minitest-retry`, system tests only) to absorb Selenium/Turbo nondeterminism. A real regression fails all three attempts; local flakiness is usually a chromedriver/Chrome version mismatch, not a regression.
- **`gssencmode: disable`** in `database.yml` is load-bearing on macOS — libpq's Kerberos calls aren't fork-safe and segfault under parallel tests.

## Deployment

Render (Blueprint-driven, `render.yaml`) is the deploy target; a Kamal/Docker path also exists. `test/deploy/*_test.rb` guards the deploy contract — `render.yaml`, `bin/render-build.sh`, and the `Dockerfile` are asserted against, because mistakes there otherwise only surface as a broken environment. Update those tests when the deploy config changes.

`bin/render-build.sh` deliberately does **not** run migrations — `db:migrate` is the service's `preDeployCommand`, so a failed migration halts the deploy with the previous version still serving. Because migrations run during deploy, destructive changes (column drops) need to ship in a *later* deploy than the code that stops using them.

Solid Cache and Solid Queue live in the primary Postgres schema (single-database setup), created by ordinary migrations.
