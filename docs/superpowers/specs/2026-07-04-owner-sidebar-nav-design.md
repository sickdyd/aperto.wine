# Owner Area Sidebar Navigation — Design

**Date:** 2026-07-04
**Scope:** Owner-facing views only (`app/views/layouts/owner.html.erb` and the `Owner::*` controllers' pages). The public landing page and customer menu are untouched.

## Problem

The owner area is hard to navigate. Today it uses a sticky top bar plus a second
horizontal sub-nav row that only appears when a restaurant is in context. Section
links (Wine Lists, Orders, QR Code) are small `btn-xs` tabs, the restaurant name is
mixed in with the tabs, and there is no way to jump between restaurants without
going back to the index.

## Research summary

Best practices for management/admin dashboards (owners managing restaurants,
wines, orders):

- A **persistent left sidebar** is the standard pattern for admin/management UIs:
  it supports deeper hierarchies, longer lists, and stays visible so users always
  know where they are (Eleken, UX Planet, Navbar Gallery).
- **Multi-location products** (e.g. Toast POS, KitchenHub) put a **location
  context switcher** at the top of the navigation rather than modelling locations
  as top-level pages — you pick the restaurant, then all nav applies to it.
- Keep the item count small, one clear label + icon per destination, avoid
  nesting when a flat list works (Eleken, cieden restaurant-management case study).
- On mobile, the sidebar collapses into an **off-canvas drawer** behind a
  hamburger button.

daisyUI 5 (already a dependency) ships this exact layout as the `drawer`
component: `drawer lg:drawer-open` renders an off-canvas drawer on small screens
and a fixed, always-open sidebar on `lg+`, with no JavaScript (checkbox toggle).

## Approaches considered

1. **daisyUI `drawer` layout** (chosen) — native to the existing component
   library, zero JS, responsive out of the box.
2. Hand-rolled CSS grid sidebar + Stimulus controller for mobile toggle — more
   code to maintain, no benefit over the drawer.
3. Keep top nav, enlarge the sub-nav — does not solve discoverability or
   restaurant switching; rejected.

## Design

`app/views/layouts/owner.html.erb` becomes a `drawer lg:drawer-open` shell:

- **Sidebar** (`drawer-side`, fixed 18rem, `bg-base-200`-tinted, right border):
  - **Brand** — "aperto.wine" linking to the restaurants index.
  - **Restaurant switcher** — a `<details class="dropdown">` listing all of the
    owner's restaurants (current one highlighted), plus "All restaurants" and
    "New restaurant" actions. Shown whenever the owner has restaurants.
  - **Section nav** (only when a restaurant is in context, i.e. `@restaurant`
    is persisted): Overview, Wine Lists, Orders, QR Code, Settings — daisyUI
    `menu` with icons and `menu-active` state derived from controller/action.
    When no restaurant is in context the nav shows a single "My Restaurants"
    item.
  - **Footer** — user name + Sign out button, pinned to the bottom.
- **Content area** (`drawer-content`):
  - Mobile-only top bar (`lg:hidden`): hamburger (`drawer-button` label) + brand.
  - Flash messages, then `<main>` with the existing max-width container.

Active-state mapping:

| Item        | Active when                                             |
|-------------|---------------------------------------------------------|
| Overview    | `restaurants#show`                                      |
| Wine Lists  | controllers `wine_lists`, `wine_list_items`, `wines`    |
| Orders      | controller `orders`                                     |
| QR Code     | controller `qr_codes`                                   |
| Settings    | `restaurants#edit` / `restaurants#update`               |

The switcher needs the owner's restaurants in every owner view:
`Owner::BaseController` gains a `before_action` that sets
`@sidebar_restaurants = current_user.restaurants.order(:name)` (one small,
indexed query; no N+1).

The sidebar markup is extracted to `app/views/owner/shared/_sidebar.html.erb`
to keep the layout small.

i18n: new `owner.nav.*` keys (overview, settings, new_restaurant,
all_restaurants, select_restaurant, open_menu) in `en.yml` and `it.yml`;
existing keys reused for Wine Lists / Orders / QR Code / My Restaurants.

## Error handling / edge cases

- Owner with zero restaurants: switcher hidden, nav shows "My Restaurants";
  index page keeps its empty state.
- `restaurants#new/create` and non-restaurant pages: no section nav, switcher
  still available.
- Link labels chosen to avoid Capybara ambiguity with existing page-level
  buttons ("Add Restaurant" stays unique to the index page).

## Testing

- Update/extend system tests: sidebar is visible on owner pages, section links
  navigate to Wine Lists / Orders / QR Code, restaurant switcher switches
  context, mobile hamburger reveals the drawer.
- Existing tests visit paths directly and assert on page content, so they keep
  passing; labels were checked for ambiguity.
