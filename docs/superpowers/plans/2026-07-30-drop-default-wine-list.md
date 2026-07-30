# Drop the default "All Wines" list; curated lists only

## Context

The wine lists page currently shows a synthetic **"All Wines"** row that is not a
`WineList` record. It is hardcoded in `app/views/owner/wine_lists/index.html.erb:28-50`
and toggled by a boolean column `restaurants.all_wines_list_active`. Its pencil
button links to the wines index, not to the list builder — so the default list
is the one list that **cannot** use the drag-and-drop builder built on this
branch. Ordering it means opening each wine's edit form and typing an integer
into a `position` number field.

This plan removes the special case. After it: only real, owner-created
`WineList` records exist. To reproduce the old "everything on the menu"
behaviour an owner creates one list and clicks a new **"Add all wines"** button.

Two product decisions were made by the human partner before planning:

1. **Menu layout** — a curated list renders **grouped by colour**, preserving
   today's customer-facing look (colour headers + jump nav). Drag reorders
   **within** a colour group only.
2. **Existing data** — **clean drop, no backfill**. The column is removed
   outright. Existing restaurants start with zero lists and an empty menu until
   an owner creates one. This is acceptable; the data is disposable.

## Global Constraints

These bind every task. Copy them verbatim into reviewer prompts.

- **Wine colour enum order is canonical**: `red: 0, white: 1, rose: 2,
  sparkling: 3, dessert: 4` (`app/models/wine.rb:8`). Every colour grouping —
  owner builder, customer menu, jump nav — renders colours in this enum order,
  never alphabetically and never by insertion.
- **`wine_list_items.position` stays globally unique within a list**, not
  per-colour. Colour grouping is a *presentation* concern applied on top of a
  single flat position sequence. Do not add a per-colour position column and do
  not scope position to colour.
- **Drag-and-drop enhances, never replaces, the button controls.** The
  "Add to list" button, the delete button and the `position` number field must
  keep working with JavaScript disabled. Every new action needs a non-JS
  `button_to`/form path.
- **No backfill migration.** Remove `restaurants.all_wines_list_active` and
  every reference to it. Do not create replacement `WineList` records.
- **DOM ids derive from record ids and enum keys, never display names**
  (existing rule, see `app/helpers/menus_helper.rb:16`). List/colour section ids
  must stay collision-free now that several lists each have colour sections.
- **i18n: both `en.yml` and `it.yml`** are updated for every key added or
  removed. No orphaned keys left behind, no key present in one locale only.
- Rails/Ruby house style: run `rubocop` and `brakeman` before each commit; both
  must be clean.

## Verification

Each task runs the test files it touches. Full-suite runs happen once, at the
end, not per task.

---

## Task 1 — Remove the default list from the owner side

**Files**

- new migration `db/migrate/*_remove_all_wines_list_active_from_restaurants.rb`
- `db/schema.rb` (regenerated)
- `config/routes.rb`
- `app/controllers/owner/wine_lists_controller.rb`
- `app/views/owner/wine_lists/index.html.erb`
- `config/locales/en.yml`, `config/locales/it.yml`
- `test/integration/owner/wine_lists_controller_test.rb`
- `test/system/owner_wine_lists_test.rb`

**Requirements**

1. Migration: `remove_column :restaurants, :all_wines_list_active, :boolean,
   default: true, null: false`. Give the full column definition so the migration
   is reversible.
2. Remove the `patch :toggle_all_wines` collection route (`config/routes.rb:32`)
   and the `toggle_all_wines` action (`app/controllers/owner/wine_lists_controller.rb:43-45`).
3. `app/views/owner/wine_lists/index.html.erb`: delete the synthetic default-list
   block (lines 27-50, the `<div>` carrying the comment
   `Default "All Wines" list — always present…`). The page now renders only
   `@wine_lists`.
4. The page currently only renders the filter + list container `if @wine_lists.any?`
   — with the default row gone, a restaurant with no lists would render a bare
   heading. Add an empty state in the `else` branch: a short line of copy plus
   the existing "Add" call to action pointing at
   `new_owner_restaurant_wine_list_path(@restaurant)`. New i18n keys
   `owner.wine_lists.empty_title` and `owner.wine_lists.empty_body`.
5. Remove now-orphaned keys `owner.wine_lists.all_wines` and
   `owner.wine_lists.default` from both locales. **Keep**
   `owner.wine_lists.manage_wines` — it is still used by `_members.html.erb:50`.
   Do not touch `menu.all_wines` in this task; Task 2 owns it.
6. Tests: delete the three `toggle_all_wines` tests
   (`test/integration/owner/wine_lists_controller_test.rb:101-120`). In
   `test/system/owner_wine_lists_test.rb`, remove the two assertions that the
   default list is always present (lines 30 and 99) — replace with an assertion
   that a restaurant with no lists shows the new empty state.

**Note for the implementer:** regenerate `db/schema.rb` against a scratch
database, never the shared development database.

---

## Task 2 — Customer menu: colour groups within each list

**Files**

- `app/helpers/menus_helper.rb`
- `app/controllers/menus_controller.rb`
- `app/views/menus/show.html.erb`
- `config/locales/en.yml`, `config/locales/it.yml`
- `test/integration/menus_controller_test.rb`
- `test/system/public_menu_test.rb`
- `test/system/menu_search_test.rb`

**Requirements**

1. `MenusHelper#renderable_wine_lists` currently returns `[[list, items]]`. Change
   it to return `[[list, colour_groups]]` where `colour_groups` is an ordered
   collection of `[colour, items]` pairs in **wine colour enum order** (see
   Global Constraints). Within a colour, items stay sorted by
   `[item.position, item.id]` as today. Colours with no items are omitted; lists
   left with no items at all are dropped, as today.
2. `MenusHelper#menu_nav_sections` — signature becomes
   `menu_nav_sections(rendered_lists)`; the `color_groups` argument goes away.
   It returns one `[dom_id, label]` pair per rendered **list × colour** section,
   in page order:
   - `dom_id` is `"list-#{list.id}-#{colour}"`
   - `label` is the translated colour name (`t("owner.wines.colors.#{colour}")`)
     when only one list renders, or `"#{list.name} · #{colour_name}"` when more
     than one list renders — so chips stay unambiguous with several lists.
3. `app/controllers/menus_controller.rb`: remove `@show_all_wines` (line 11) and
   the now-unused `@wines` assignment (line 12). Verify `@wines` has no other
   reader in `app/views/menus/` before deleting it.
4. `app/views/menus/show.html.erb`: delete the `all_wines` / `color_groups` /
   `rendered_any` preamble (lines 20-22) and the entire trailing all-wines
   section (from `<% if all_wines.any? %>` at line 58 through its `end`). Guard
   the page on `rendered_lists.any?`. Each list renders its name and optional
   season as today, then one `<section>` per colour with
   `id="list-#{list.id}-#{colour}"`, the existing `wine_color_dot` + colour
   heading treatment used by the old all-wines section, and the wine rows.
   Each colour section keeps `data-list-filter-target="group"` so search still
   hides empty groups, and keeps `scroll-mt-20`.
5. Remove the `menu.all_wines` key from both locales — with no default list
   there is no "All Wines" heading. Verify no other reference survives.
6. Tests: `test/integration/menus_controller_test.rb:74,83` and
   `test/system/public_menu_test.rb:115` set `all_wines_list_active: false` on a
   fixture; that column no longer exists, so rework those cases to express the
   same intent using lists (e.g. a restaurant whose only list is inactive).
   Add coverage that a list renders colour subsections in enum order.
   `test/system/menu_search_test.rb` must still pass — confirm search filters
   across the new per-colour groups.

---

## Task 3 — "Add all wines" button

**Files**

- `config/routes.rb`
- `app/controllers/owner/wine_list_items_controller.rb`
- `app/views/owner/wine_lists/_members.html.erb`
- `config/locales/en.yml`, `config/locales/it.yml`
- `test/controllers/owner/wine_list_items_controller_test.rb`
- `test/system/owner/wine_list_builder_test.rb`

**Requirements**

1. Route: add `post :create_all` to the existing `wine_list_items` collection
   block in `config/routes.rb` (beside `patch :sort`).
2. `Owner::WineListItemsController#create_all`: add every wine belonging to the
   restaurant that is **not already on the list**, appended after the existing
   items, in `Wine.by_position` order. Assign positions continuing from the
   current maximum. Use a single bulk insert — follow the bulk-write approach
   already used by `#sort` (commit `cdb8c89`), not a per-row `create!` loop.
   Wrap in a transaction.
3. The action must be idempotent-safe: adding all wines twice must not create
   duplicate `wine_list_items`, and must not error.
4. Respond with the same `turbo_stream` repaint of the `wine_list_members`
   target that `#create` uses, including the flash partial, plus an HTML
   redirect fallback for the non-JS path.
5. Authorisation must match the sibling actions — a user who does not own the
   restaurant gets the same rejection `#create` and `#sort` give. Add a test for
   this; the ledger notes the missing `sort` auth test as an outstanding Minor,
   so do not repeat that gap here.
6. View: in `_members.html.erb`, add the button to the available-wines column
   header, rendered only when `available_wines.any?`. Use `button_to` so it
   works without JavaScript. New i18n key
   `owner.wine_lists.members.add_all` (both locales) — English "Add all wines",
   Italian "Aggiungi tutti i vini". Style it with the existing small-button
   classes used in that column; do not invent a new button variant.
7. The button adds **all** available wines and deliberately ignores whatever is
   typed in the filter box — the filter is a client-side display filter only.
8. Tests: controller coverage for the happy path, the no-duplicates case, the
   empty-available case, and authorisation. System coverage that clicking the
   button moves every available wine onto the list.

---

## Task 4 — Per-colour drag groups in the list builder

**Files**

- `app/views/owner/wine_lists/_members.html.erb`
- `app/views/owner/wine_lists/_member_item.html.erb`
- `app/views/owner/wine_lists/_available_wine.html.erb`
- `app/javascript/controllers/sortable_controller.js`
- `config/locales/en.yml`, `config/locales/it.yml`
- `test/system/owner/wine_list_builder_test.rb`

**Requirements**

1. The members column is split into one drop container per wine colour, each
   with a colour heading (reuse `wine_color_dot`). Render a container for every
   colour that has **either** an item on the list **or** an available wine of
   that colour — so any wine that can be dragged always has a target, while
   unused colours stay hidden. Containers render in wine colour enum order.
2. Each member container carries `data-color="<colour>"` and is a
   `data-sortable-target="members"` (now a **multi**-target — the controller
   uses `membersTargets`, plural).
3. `_member_item.html.erb` and `_available_wine.html.erb` rows each carry
   `data-color="<wine colour>"` so the controller can validate a drop.
4. `sortable_controller.js`:
   - Build one `Sortable` per member container. Keep the shared group name
     `"wine-list"`, and add a `put` callback that accepts a dragged element only
     when `dragEl.dataset.color === to.el.dataset.color`. This blocks both
     cross-colour drops from the available column and cross-colour moves
     between member containers.
   - `memberIds()` returns ids concatenated across **all** member containers in
     document order, so the flat global position sequence is preserved (see
     Global Constraints).
   - `onStart` snapshot and `restoreSnapshot()` must handle multiple containers
     — record which container each row belonged to and restore rows to their
     original container and order on a failed PATCH. The current single-container
     implementation (lines 116-125) will silently mis-restore otherwise.
   - Preserve the existing touch behaviour verbatim: `delay: 150`,
     `delayOnTouchOnly: true`, `touchStartThreshold: 5`, and the
     `filter` / `preventOnFilter: false` configuration on the available column.
     Commit `7045eeb` fixed this specifically; do not regress it.
5. An empty colour container needs a visible drop affordance (a dashed
   placeholder with a short hint) and enough height to be a usable drop target.
   New i18n key `owner.wine_lists.members.empty_color` in both locales.
6. Update the screen-reader drag hint (`owner.wine_lists.members.drag_hint`) to
   say ordering is within a colour group.
7. Tests: system coverage that (a) reordering within a colour persists,
   (b) dragging a wine into its matching colour group works, (c) a cross-colour
   drop is rejected and leaves the list unchanged.

---

## Out of scope

- `wines.position` and its number field in `app/views/owner/wines/_form.html.erb:126`
  stay as they are. That column still orders the owner wines index and the
  available-wines column; it no longer has any effect on the customer menu.
- Drag-and-drop for reordering the wine **lists** themselves on the index page.
- The Minor findings already recorded in the ledger from Tasks 1-4 of the
  previous feature. The final whole-branch review triages those separately.
