# Address Autocomplete for Restaurant Owner Form — Design

**Date:** 2026-07-05
**Status:** Approved
**Branch:** feat/address-autocomplete

## Goal

Replace the manual latitude/longitude inputs on the owner restaurant form with
address autocomplete. The owner types an address, picks a suggestion, and the
coordinates are filled automatically into hidden fields. Uses a free provider
(Photon, no API key). Coordinates are never shown to the owner.

## Decisions

- **Provider:** Photon (`photon.komoot.io`) — free, keyless, built for
  search-as-you-type on OpenStreetMap data. OSM's public Nominatim forbids
  autocomplete, so it is used neither directly nor indirectly for type-ahead.
- **Region:** Italy first. Country scope is configuration, not code:
  `Rails.application.config.x.geocoding.country_codes = ["IT"]`. Set to `[]`
  to go worldwide later. Suggestions are also location-biased toward Italy's
  centroid (Photon `lat`/`lon` bias params).
- **No visible coordinates:** the visible latitude/longitude number inputs are
  removed from the form and replaced with hidden fields.
- **Fallback:** if the owner types an address without picking a suggestion,
  the server geocodes it once on save (never blocking the save on failure).

## Architecture

### 1. Backend suggestion endpoint

`GET /owner/address_suggestions?q=...` handled by
`Owner::AddressSuggestionsController < Owner::BaseController` (auth-protected).

- Calls Photon `https://photon.komoot.io/api` with `q`, `limit=5`, Italy
  centroid bias, 2s open/read timeouts.
- Filters returned features to the configured `country_codes` (via each
  feature's `properties.countrycode`); empty config = no filtering.
- Caches responses in `Rails.cache` for 1 day, keyed on the normalized query.
- Rate limited with Rails 8 built-in `rate_limit` (10 requests / 3 seconds per
  session) because it fans out to a third-party service.
- Renders an HTML `<ul>` fragment; each `<li>` carries
  `data-autocomplete-value` (formatted address), `data-latitude`,
  `data-longitude`. Includes a small "© OpenStreetMap contributors"
  attribution footer (ODbL requirement).
- Queries shorter than 3 chars return an empty body without calling Photon.
- Photon errors/timeouts return an empty list — the form degrades to a plain
  text field and never blocks.

### 2. Frontend

- Pin the maintained `stimulus-autocomplete` package via importmap. It
  provides the accessible combobox: debounce, min-length 3, keyboard
  navigation, ARIA roles.
- A thin custom Stimulus controller (`address-autocomplete`) wraps it:
  listens for the `autocomplete.change` event and copies the selected
  suggestion's `data-latitude`/`data-longitude` into the hidden fields. It
  also clears the hidden fields when the address text is edited after a
  selection (stale coordinates must not survive an address change; the
  server-side fallback then re-geocodes).
- `_form.html.erb`: address becomes the autocomplete input;
  `f.hidden_field :latitude` / `f.hidden_field :longitude` replace the
  visible number inputs. Manual typing keeps working — it is still a text
  input.

### 3. Server-side fallback geocoding

- Add the `geocoder` gem configured with its Photon lookup (2s timeout, same
  country config).
- On `Restaurant`:
  `after_validation :geocode, if: -> { address_changed? && latitude.blank? }`
  wrapped so any geocoding failure is logged and never blocks the save.
- Coordinates stay nullable; nothing consumes them yet, so a failed geocode
  is non-fatal.

## Data flow

Owner types ≥3 chars → stimulus-autocomplete debounces → our endpoint →
Photon → filtered HTML suggestions → owner picks one → address field + hidden
lat/lng populated → normal form submit. No suggestion picked → save proceeds →
model fallback geocodes once server-side.

## Error handling

- Photon down/slow: endpoint returns empty suggestions; form still usable.
- Fallback geocode failure: rescued and logged; save succeeds with blank
  coordinates.
- Empty/short queries: no Photon call.

## Testing

No test may hit the network or read `.env` / `.env.development`.

- **Endpoint (controller/integration):** auth required; Photon stubbed with
  WebMock; country filtering; caching behavior; rate limiting; short-query
  and Photon-error paths.
- **Model:** fallback geocoding via Geocoder test mode (stubbed lookup):
  geocodes when address changed and coords blank, skips when coords present,
  save succeeds when lookup raises.
- **System:** form renders the autocomplete input and hidden coordinate
  fields (no visible lat/lng inputs); picking a stubbed suggestion fills the
  hidden fields.

## Out of scope

- Reverse geocoding, maps, and any UI that displays coordinates.
- Self-hosting Photon (revisit if public-instance limits are ever hit).
- Autocomplete on customer-facing forms.
