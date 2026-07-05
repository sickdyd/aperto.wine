# Wine-Searcher Type-Ahead Autofill — Design

**Date:** 2026-07-05
**Branch:** `feat/wine-searcher-autofill`
**Status:** Approved (approach A of three considered)

## Goal

When a restaurant owner adds or edits a wine, typing the wine name shows a
debounced dropdown of Wine-Searcher matches. Picking one autofills the
descriptive fields — producer, region, grape variety, vintage year, and color
(when derivable). Description and all price fields are never touched. Manual
entry keeps working exactly as today; the feature degrades to a no-op whenever
the API is unavailable or unconfigured.

## Context and constraints

- Wine-Searcher's API is a Trade product: key granted on application, trial
  tier is 100 calls/day. The key is not yet in hand; the integration is built
  against documented request/response shapes with stubs, and verified live
  once the key arrives.
- The exact response schema (XML vs JSON, field names) is confirmed only with
  API access. All parsing is isolated in one method of the client so live
  verification can only require changes there.
- The key is a secret: it lives in Rails credentials
  (`wine_searcher.api_key`) with `ENV["WINE_SEARCHER_API_KEY"]` as fallback,
  and must never reach the browser. All calls go through a server-side proxy.
- A parallel branch `feat/wine-enrichment-fields` adds `abv`, `style`,
  `image_url`, tasting-profile and certification fields to `Wine`, but does
  not touch the wine form. This feature targets only fields that exist on
  `main`; the client's result struct is designed so `style`/`abv`/`image_url`
  can be added as fill targets after that branch merges.

## Architecture

```
name input (Stimulus wine-autofill, 350ms debounce, min 3 chars)
  → GET /owner/wine_lookups?q=… (JSON, authenticated, rate-limited)
    → WineSearcher::Client#search
      → Rails.cache (24h TTL, normalized query key, negative caching)
      → on miss: GET Wine-Searcher API (api_key + winename params)
  ← [{ name, producer, region, grape_variety, vintage_year, color }, …]
→ dropdown renders; selection fills form fields
```

## Components

### `app/services/wine_searcher/client.rb`

- Owns all HTTP concerns: endpoint, `api_key` + `winename` params, strict
  timeouts (2s open / 3s read), User-Agent.
- `#search(query)` returns an array of `WineSearcher::Result` structs
  (`name`, `producer`, `region`, `grape_variety`, `vintage_year`, `color`,
  with room for `style`/`abv`/`image_url` later).
- Caching: `Rails.cache.fetch("wine_searcher/v1/#{normalized_query}",
  expires_in: 24.hours)`; empty result sets are cached too (negative caching)
  to protect the 100/day trial quota.
- `#configured?` — true only when a key is present.
- Color derivation: mapped from Wine-Searcher's wine style/type only for
  unambiguous cases (red/white/rosé/sparkling/dessert); otherwise `nil` and
  the form's color select is left untouched.
- Failure policy: timeout, non-200, quota-exceeded, or parse error → log a
  warning with context, return `[]`. Never raise to callers.

### `Owner::WineLookupsController#index`

- Route: `GET /owner/wine_lookups` (JSON only), inside the authenticated
  owner namespace; not nested under restaurant (wine data is not
  restaurant-scoped).
- Validates `q`: strip, min length 3, max length 100; short/blank queries
  return `[]` without touching the client.
- Rate limiting via Rails' built-in `rate_limit` (10 requests / 20 seconds
  per session) as a second guard on the upstream quota.
- When `WineSearcher::Client#configured?` is false, returns `[]` — the form
  behaves exactly as today for environments without a key.

### `app/javascript/controllers/wine_autofill_controller.js`

- Attached to the name field wrapper in
  `app/views/owner/wines/_form.html.erb`.
- Debounce 350ms, min 3 chars, `AbortController` cancels in-flight requests
  on new input.
- DaisyUI dropdown listing `name — producer (region)`; keyboard navigation
  (ArrowUp/Down, Enter, Escape), click selection, ARIA combobox roles.
- On selection: fills name, producer, region, grape variety, vintage year,
  and color (only when present in the payload). Fields the user already
  edited by hand after the last selection are overwritten only by an explicit
  new selection — never by typing alone.
- Network or non-200 → dropdown shows nothing; typing continues normally.

### Form integration

- `_form.html.erb`: wrap the basic-info fieldset with the controller, add
  `data-wine-autofill-target` attributes to the five fillable inputs and
  `data-wine-autofill-url-value` for the endpoint. No layout redesign.
- i18n: dropdown strings (`no_results`, `searching`) added to `en.yml` and
  `it.yml` under `owner.wines.autofill`.

## Error handling summary

| Failure | Behavior |
| --- | --- |
| No API key configured | Endpoint returns `[]`; UI silent |
| Timeout / non-200 / parse error | Client logs warning, returns `[]` |
| Upstream quota exhausted | Same as above (logged distinctly) |
| Rate limit hit (local) | 429; Stimulus controller treats as empty |
| Query too short | `[]` without client call |

No Wine-Searcher failure ever blocks manual entry or surfaces an error to the
owner beyond an empty dropdown.

## Testing

- **Client unit tests** — WebMock-stubbed HTTP: happy path, empty results,
  timeout, non-200, malformed body, caching behavior (second call hits cache),
  negative caching, unconfigured mode. Fixtures follow the documented response
  shape; no real key, no `.env` reads (per repo test rules, `.env.test` only).
- **Controller tests** — auth required, `q` validation, JSON shape, keyless
  fallback, rate limiting.
- **System test** — stubbed client (no HTTP): type name → dropdown appears →
  select → assert producer/region/grape/vintage/color populated; and a
  keyboard-only path.

## Out of scope (explicitly)

- Price autofill or price hints from Wine-Searcher.
- Description autofill.
- Label-photo recognition (separate future feature).
- Persistent local reference table (approach B — deliberately deferred; the
  client interface is the seam where it would slot in).

## Rollout

1. Merge with stubs; endpoint inert until a key is configured.
2. When the trial key arrives: add to credentials, verify parsing against one
   live response in the console, adjust the one parse method if the
   documented shape differs, confirm with the client unit fixtures updated to
   the real shape.
3. Monitor logs for quota warnings; revisit approach B (local reference
   table) if the 100/day trial quota is limiting before upgrade.
