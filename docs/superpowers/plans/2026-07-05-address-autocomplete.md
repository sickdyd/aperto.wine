# Owner Address Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Address autocomplete on the owner restaurant form: suggestions from Photon (free, keyless, OpenStreetMap), coordinates auto-filled into hidden fields, server-side geocoding fallback on save.

**Architecture:** A `Geocoding` service module wraps the `geocoder` gem's Photon lookup (Italy-biased, country-filtered, cached). A thin auth-protected `Owner::AddressSuggestionsController` renders `<li role="option">` fragments consumed by the maintained `stimulus-autocomplete` package; a tiny companion Stimulus controller copies the picked suggestion's coordinates into hidden fields. `Restaurant` geocodes server-side on save when the address changed and no coordinates were provided.

**Tech Stack:** Rails 8.1.3 (minitest, importmap, Propshaft, Tailwind 4 + daisyUI, solid_cache in prod / memory store in dev), `geocoder ~> 1.8` (1.8.6), `stimulus-autocomplete` 3.1.0, `webmock` (test only).

**Spec:** `docs/superpowers/specs/2026-07-05-address-autocomplete-design.md`

## Global Constraints

- Photon endpoint: `https://photon.komoot.io/api` — the ONLY external service; public OSM Nominatim must not be used (its policy forbids autocomplete).
- Country scope is config, not code: `Rails.application.config.x.geocoding.country_codes = [ "IT" ]`; empty array = worldwide.
- Suggestion bias point (Italy centroid): lat `42.5`, lon `12.5`. Limit `5` results. Min query length `3`. Cache TTL `1.day`. Photon timeout `2` seconds.
- Rate limit on the suggestions endpoint: `10` requests per `3.seconds`, respond `429`.
- Coordinates are never visible in the UI — hidden fields only.
- Attribution "© OpenStreetMap contributors" must appear under the suggestion list (ODbL).
- Tests must never hit the network or read `.env`/`.env.development`. WebMock with `allow_localhost: true` (Capybara needs localhost).
- Commit messages: conventional commits (`feat:`, `test:`, `chore:`), NO `Co-Authored-By` lines. Lefthook pre-commit runs rubocop/brakeman/audits automatically.
- Ruby style: rubocop-rails-omakase (note the repo uses spaces inside array literals: `[ "IT" ]`).
- Run commands from the worktree root: `/Users/robertoreale/webdev/aperto.wine/.claude/worktrees/address-autocomplete`.

---

### Task 1: Gems and hermetic test infrastructure

**Files:**
- Modify: `Gemfile`
- Modify: `config/environments/test.rb:23`
- Modify: `test/test_helper.rb`

**Interfaces:**
- Produces: `stub_photon(features)` and `photon_feature(...)` test helpers (module `PhotonStubs`, included in `ActiveSupport::TestCase`); a global per-test default stub (Photon returns no features) plus `Rails.cache.clear`; memory cache store in the test env.

- [ ] **Step 1: Add gems**

In `Gemfile`, after the `gem "active_storage_validations", "~> 3.0"` line, add:

```ruby
# Geocoding (address → coordinates) via OpenStreetMap/Photon [https://github.com/alexreisner/geocoder]
gem "geocoder", "~> 1.8"
```

In the `group :test do` block, after `gem "minitest-retry"`, add:

```ruby
# Stub external HTTP (Photon geocoding) — tests must never hit the network
gem "webmock"
```

Run: `bundle install`
Expected: `Bundle complete`, Gemfile.lock updated with geocoder 1.8.x and webmock 3.26.x.

- [ ] **Step 2: Switch the test cache store to memory**

In `config/environments/test.rb`, replace:

```ruby
  config.cache_store = :null_store
```

with:

```ruby
  # Memory store (not the default null store) so Rails.cache-backed behavior —
  # suggestion caching and controller rate limiting — is exercisable in tests.
  # test_helper.rb clears the cache before every test to keep them isolated.
  config.cache_store = :memory_store
```

- [ ] **Step 3: Wire WebMock and Photon stub helpers**

Replace the entire contents of `test/test_helper.rb` with:

```ruby
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Tests must never hit the network. Capybara drives the local app server and
# Selenium's chromedriver listens on localhost, so localhost stays reachable.
WebMock.disable_net_connect!(allow_localhost: true)

module PhotonStubs
  PHOTON_API = %r{\Ahttps://photon\.komoot\.io/api}

  def stub_photon(features)
    stub_request(:get, PHOTON_API).to_return(
      status: 200,
      body: { "type" => "FeatureCollection", "features" => features }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def photon_feature(street: "Via Roma", housenumber: "42", postcode: "20121", city: "Milano",
                     country: "Italia", countrycode: "IT", name: nil, lat: 45.4642, lon: 9.19)
    {
      "type" => "Feature",
      "geometry" => { "type" => "Point", "coordinates" => [ lon, lat ] },
      "properties" => {
        "name" => name, "street" => street, "housenumber" => housenumber,
        "postcode" => postcode, "city" => city,
        "country" => country, "countrycode" => countrycode
      }.compact
    }
  end
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    include PhotonStubs

    # Default: Photon knows nothing, and no cache/rate-limit state leaks
    # between tests. Tests needing suggestions declare their own
    # stub_photon(...), which takes precedence over this default.
    setup do
      stub_photon([])
      Rails.cache.clear
    end
  end
end

module ActionDispatch
  class IntegrationTest
    def sign_in_as(user, password: "password123")
      post sign_in_path, params: { email: user.email, password: password }
      follow_redirect!
    end
  end
end
```

- [ ] **Step 4: Run the full suite to prove the infra is inert**

Run: `bin/rails test`
Expected: same pass count as before this task, 0 failures/errors (no existing code performs external HTTP).

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock config/environments/test.rb test/test_helper.rb
git commit -m "chore: add geocoder and webmock with hermetic test setup"
```

---

### Task 2: Geocoding service module

**Files:**
- Create: `config/initializers/geocoding.rb`
- Create: `app/services/geocoding.rb`
- Test: `test/services/geocoding_test.rb`

**Interfaces:**
- Consumes: `PhotonStubs` helpers from Task 1.
- Produces:
  - `Geocoding.suggestions(query) → Array<{label: String, latitude: Numeric, longitude: Numeric}>` (empty array on short query, filtered-out countries, or lookup failure)
  - `Geocoding.allowed_country?(code) → Boolean` (case-insensitive ISO alpha-2 check; `true` for everything when config list is empty)
  - `Geocoding.country_codes → Array<String>`
  - Geocoder gem globally configured for Photon (used by Task 4's `geocode` too).

- [ ] **Step 1: Write the failing tests**

Create `test/services/geocoding_test.rb`:

```ruby
require "test_helper"

class GeocodingTest < ActiveSupport::TestCase
  test "suggestions returns empty for queries shorter than 3 chars without calling photon" do
    assert_equal [], Geocoding.suggestions("Vi")
    assert_equal [], Geocoding.suggestions(nil)
    assert_equal [], Geocoding.suggestions("  V  ")
    assert_not_requested :get, PhotonStubs::PHOTON_API
  end

  test "suggestions maps photon features to labeled coordinates" do
    stub_photon([ photon_feature ])

    suggestions = Geocoding.suggestions("Via Roma 42")

    assert_equal 1, suggestions.length
    assert_equal "Via Roma 42, 20121 Milano, Italia", suggestions.first[:label]
    assert_in_delta 45.4642, suggestions.first[:latitude]
    assert_in_delta 9.19, suggestions.first[:longitude]
  end

  test "suggestions prepends the POI name when present" do
    stub_photon([ photon_feature(name: "Osteria del Borgo") ])

    assert_equal "Osteria del Borgo, Via Roma 42, 20121 Milano, Italia",
                 Geocoding.suggestions("Osteria del Borgo").first[:label]
  end

  test "suggestions filters out countries not in the configured list" do
    stub_photon([
      photon_feature,
      photon_feature(street: "Rue de Rivoli", city: "Paris", postcode: "75001",
                     country: "France", countrycode: "FR", lat: 48.8606, lon: 2.3376)
    ])

    suggestions = Geocoding.suggestions("Rivoli")

    assert_equal 1, suggestions.length
    assert_includes suggestions.first[:label], "Milano"
  end

  test "suggestions allows all countries when the configured list is empty" do
    original = Rails.application.config.x.geocoding.country_codes
    Rails.application.config.x.geocoding.country_codes = []
    stub_photon([ photon_feature(countrycode: "FR", country: "France") ])

    assert_equal 1, Geocoding.suggestions("Rue de Rivoli").length
  ensure
    Rails.application.config.x.geocoding.country_codes = original
  end

  test "suggestions sends limit, bias and language params to photon" do
    stub_photon([])

    Geocoding.suggestions("Via Roma 42")

    assert_requested :get, PhotonStubs::PHOTON_API, times: 1 do |request|
      params = Rack::Utils.parse_query(request.uri.query)
      params["limit"] == "5" && params["lat"] == "42.5" && params["lon"] == "12.5" &&
        %w[en it].include?(params["lang"])
    end
  end

  test "suggestions caches results per query" do
    stub_photon([ photon_feature ])

    2.times { Geocoding.suggestions("Via Roma 42") }

    assert_requested :get, PhotonStubs::PHOTON_API, times: 1
  end

  test "suggestions returns empty when photon times out" do
    stub_request(:get, PhotonStubs::PHOTON_API).to_timeout

    assert_equal [], Geocoding.suggestions("Via Roma 42")
  end

  test "allowed_country? is case-insensitive and nil-safe" do
    assert Geocoding.allowed_country?("it")
    assert Geocoding.allowed_country?("IT")
    assert_not Geocoding.allowed_country?("FR")
    assert_not Geocoding.allowed_country?(nil)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/geocoding_test.rb`
Expected: FAIL — `NameError: uninitialized constant Geocoding` (or similar) on every test.

- [ ] **Step 3: Write the initializer and module**

Create `config/initializers/geocoding.rb`:

```ruby
# Country scope for address suggestions and fallback geocoding, as ISO
# 3166-1 alpha-2 codes. Add codes to expand to new markets; an empty
# array means worldwide.
Rails.application.config.x.geocoding.country_codes = [ "IT" ]

# Photon (photon.komoot.io): free, keyless geocoding on OpenStreetMap data,
# built for search-as-you-type. The public instance is best-effort — every
# caller must degrade gracefully when it is unavailable.
Geocoder.configure(
  lookup: :photon,
  use_https: true,
  timeout: 2,
  units: :km
)
```

Create `app/services/geocoding.rb`:

```ruby
# Address geocoding via Photon (OpenStreetMap data). Used by the owner
# address autocomplete endpoint and Restaurant's fallback geocoding.
# Results are ODbL-licensed: any UI showing them must attribute
# "© OpenStreetMap contributors".
module Geocoding
  SUGGESTION_LIMIT = 5
  MIN_QUERY_LENGTH = 3
  CACHE_TTL = 1.day
  # Geographic center of Italy — ranks nearby results first without
  # excluding other countries (filtering is allowed_country?'s job).
  BIAS_LATITUDE = 42.5
  BIAS_LONGITUDE = 12.5

  class << self
    def country_codes
      Rails.application.config.x.geocoding.country_codes
    end

    def allowed_country?(code)
      country_codes.empty? || country_codes.include?(code.to_s.upcase)
    end

    def suggestions(query)
      query = query.to_s.strip
      return [] if query.length < MIN_QUERY_LENGTH

      Rails.cache.fetch([ "address_suggestions", I18n.locale, query.downcase ], expires_in: CACHE_TTL) do
        fetch_suggestions(query)
      end
    end

    private

    def fetch_suggestions(query)
      results = Geocoder.search(query, params: {
        limit: SUGGESTION_LIMIT,
        lat: BIAS_LATITUDE,
        lon: BIAS_LONGITUDE,
        lang: photon_lang
      })
      results.filter_map { |result| suggestion_from(result) }
    rescue StandardError => e
      Rails.logger.warn("Geocoding.suggestions failed: #{e.class}: #{e.message}")
      []
    end

    def suggestion_from(result)
      properties = result.data["properties"] || {}
      return nil unless allowed_country?(properties["countrycode"])

      longitude, latitude = result.data.dig("geometry", "coordinates")
      return nil if latitude.nil? || longitude.nil?

      { label: format_label(properties), latitude: latitude, longitude: longitude }
    end

    # "Name, Street 42, 20121 Milano, Italia" — blank parts skipped,
    # consecutive duplicates collapsed.
    def format_label(properties)
      street = [ properties["street"], properties["housenumber"] ].compact.join(" ")
      city = [ properties["postcode"], properties["city"] ].compact.join(" ")
      [ properties["name"], street, city, properties["country"] ]
        .filter_map { |part| part.to_s.strip.presence }
        .uniq
        .join(", ")
    end

    # Photon supports en/de/fr/it; fall back to English for other locales.
    def photon_lang
      %w[en it].include?(I18n.locale.to_s) ? I18n.locale.to_s : "en"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/geocoding_test.rb`
Expected: PASS, 9 tests. If the "sends limit, bias and language params" test fails on the URL, inspect the actual request URL in the failure message — the Photon lookup in geocoder 1.8.6 sends `q`, plus everything under `params:` verbatim; adjust the stub assertion only if the gem renamed a param (do NOT change the module's public interface).

- [ ] **Step 5: Commit**

```bash
git add config/initializers/geocoding.rb app/services/geocoding.rb test/services/geocoding_test.rb
git commit -m "feat: add Geocoding service backed by Photon"
```

---

### Task 3: Address suggestions endpoint

**Files:**
- Modify: `config/routes.rb` (owner namespace, around line 22)
- Create: `app/controllers/owner/address_suggestions_controller.rb`
- Create: `app/views/owner/address_suggestions/index.html.erb`
- Modify: `config/locales/en.yml` + `config/locales/it.yml` (form section)
- Test: `test/integration/owner/address_suggestions_controller_test.rb`

**Interfaces:**
- Consumes: `Geocoding.suggestions(query)` from Task 2; `PhotonStubs` from Task 1; `Owner::BaseController` (existing: `authenticate_user!`, `require_owner!`, `set_sidebar_restaurants`).
- Produces: `GET /owner/address_suggestions?q=...` (path helper `owner_address_suggestions_path`) returning an HTML fragment of `<li role="option" data-autocomplete-value data-latitude data-longitude>` elements plus an attribution `<li aria-disabled="true">`; empty body when there are no suggestions. Task 5's frontend consumes exactly this shape.

- [ ] **Step 1: Write the failing tests**

Create `test/integration/owner/address_suggestions_controller_test.rb`:

```ruby
require "test_helper"

module Owner
  class AddressSuggestionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
    end

    test "index requires authentication" do
      get owner_address_suggestions_path(q: "Via Roma 42")
      assert_redirected_to sign_in_path
    end

    test "index as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_address_suggestions_path(q: "Via Roma 42")
      assert_redirected_to root_path
    end

    test "index renders suggestion options with coordinates and attribution" do
      stub_photon([ photon_feature ])
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Via Roma 42")

      assert_response :success
      assert_match %r{<li[^>]*role="option"}, response.body
      assert_match 'data-autocomplete-value="Via Roma 42, 20121 Milano, Italia"', response.body
      assert_match 'data-latitude="45.4642"', response.body
      assert_match 'data-longitude="9.19"', response.body
      assert_match "OpenStreetMap contributors", response.body
    end

    test "index escapes HTML in photon data" do
      stub_photon([ photon_feature(street: "<script>alert(1)</script>") ])
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Via Roma 42")

      assert_response :success
      refute_match "<script>alert(1)</script>", response.body
    end

    test "index returns empty body for short queries without calling photon" do
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Vi")

      assert_response :success
      assert_empty response.body.strip
      assert_not_requested :get, PhotonStubs::PHOTON_API
    end

    test "index returns empty body when photon fails" do
      stub_request(:get, PhotonStubs::PHOTON_API).to_timeout
      sign_in_as @owner

      get owner_address_suggestions_path(q: "Via Roma 42")

      assert_response :success
      assert_empty response.body.strip
    end

    test "index is rate limited" do
      sign_in_as @owner

      responses = 11.times.map do |i|
        get owner_address_suggestions_path(q: "Via Roma #{i}")
        response.status
      end

      assert_equal 429, responses.last
      assert_includes responses.first(10), 200
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/owner/address_suggestions_controller_test.rb`
Expected: FAIL — `NameError`/`NoMethodError` for `owner_address_suggestions_path` (route missing).

- [ ] **Step 3: Add route, controller, view, locale key**

In `config/routes.rb`, inside `namespace :owner do`, directly above `resources :restaurants do`, add:

```ruby
      resources :address_suggestions, only: [ :index ]
```

Create `app/controllers/owner/address_suggestions_controller.rb`:

```ruby
module Owner
  class AddressSuggestionsController < BaseController
    # The response is a bare <li> fragment — no layout, no sidebar query.
    skip_before_action :set_sidebar_restaurants

    # Every keystroke can fan out to Photon (a shared free service); cap
    # bursts per client beyond what the client-side debounce already does.
    rate_limit to: 10, within: 3.seconds, with: -> { head :too_many_requests }

    def index
      @suggestions = Geocoding.suggestions(params[:q])
      render layout: false
    end
  end
end
```

Create `app/views/owner/address_suggestions/index.html.erb`:

```erb
<% @suggestions.each do |suggestion| %>
  <li role="option"
      class="address-suggestion"
      data-autocomplete-value="<%= suggestion[:label] %>"
      data-latitude="<%= suggestion[:latitude] %>"
      data-longitude="<%= suggestion[:longitude] %>"><%= suggestion[:label] %></li>
<% end %>
<% if @suggestions.any? %>
  <li aria-disabled="true" class="address-suggestion-attribution"><%= t("owner.restaurants.form.address_suggestions_attribution") %></li>
<% end %>
```

In `config/locales/en.yml`, inside `owner: → restaurants: → form:` (after `address_placeholder`), add:

```yaml
        address_suggestions_attribution: "© OpenStreetMap contributors"
```

In `config/locales/it.yml`, same position:

```yaml
        address_suggestions_attribution: "© contributori di OpenStreetMap"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/integration/owner/address_suggestions_controller_test.rb`
Expected: PASS, 7 tests. If the rate-limit test gets 429 too early, another test in the same process polluted the counter — confirm `Rails.cache.clear` runs in the global setup (Task 1 Step 3), not just locally.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/owner/address_suggestions_controller.rb app/views/owner/address_suggestions config/locales/en.yml config/locales/it.yml test/integration/owner/address_suggestions_controller_test.rb
git commit -m "feat: owner address suggestions endpoint backed by Photon"
```

---

### Task 4: Restaurant fallback geocoding

**Files:**
- Modify: `app/models/restaurant.rb`
- Test: `test/models/restaurant_test.rb` (append tests; keep existing ones)

**Interfaces:**
- Consumes: `Geocoding.allowed_country?` from Task 2; geocoder gem's `geocoded_by`/`geocode` (configured for Photon in Task 2's initializer); `PhotonStubs`.
- Produces: on save, a `Restaurant` with a present, changed `address` and blank `latitude` gets coordinates from the first allowed-country Photon result; failures log a warning and never block the save.

- [ ] **Step 1: Write the failing tests**

Append inside the existing class in `test/models/restaurant_test.rb`:

```ruby
  # --- Fallback geocoding ---

  test "geocodes on create when address present and coordinates blank" do
    stub_photon([ photon_feature ])

    restaurant = users(:owner).restaurants.create!(name: "Nuova", address: "Via Roma 42, Milano")

    assert_in_delta 45.4642, restaurant.latitude.to_f
    assert_in_delta 9.19, restaurant.longitude.to_f
  end

  test "does not geocode when coordinates are provided" do
    users(:owner).restaurants.create!(
      name: "Nuova", address: "Via Roma 42, Milano", latitude: 45.0, longitude: 9.0
    )

    assert_not_requested :get, PhotonStubs::PHOTON_API
  end

  test "re-geocodes on update when address changes and coordinates were cleared" do
    restaurant = restaurants(:osteria)
    stub_photon([ photon_feature(street: "Via Verdi", housenumber: "7", city: "Torino",
                                 postcode: "10121", lat: 45.0703, lon: 7.6869) ])

    restaurant.update!(address: "Via Verdi 7, Torino", latitude: nil, longitude: nil)

    assert_in_delta 45.0703, restaurant.latitude.to_f
    assert_in_delta 7.6869, restaurant.longitude.to_f
  end

  test "does not geocode when address is unchanged" do
    restaurants(:osteria).update!(description: "Updated")

    assert_not_requested :get, PhotonStubs::PHOTON_API
  end

  test "skips results from countries outside the configured list" do
    stub_photon([ photon_feature(countrycode: "FR", country: "France") ])

    restaurant = users(:owner).restaurants.create!(name: "Nuova", address: "Rue de Rivoli, Paris")

    assert_nil restaurant.latitude
    assert_nil restaurant.longitude
  end

  test "save succeeds when geocoding fails" do
    stub_request(:get, PhotonStubs::PHOTON_API).to_timeout

    restaurant = users(:owner).restaurants.create!(name: "Nuova", address: "Via Roma 42, Milano")

    assert restaurant.persisted?
    assert_nil restaurant.latitude
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/restaurant_test.rb`
Expected: the new geocoding tests FAIL (latitude stays nil / photon unexpectedly not requested); existing tests still pass.

- [ ] **Step 3: Implement fallback geocoding on the model**

Replace the contents of `app/models/restaurant.rb` with:

```ruby
class Restaurant < ApplicationRecord
  belongs_to :user
  has_many :wines, dependent: :destroy
  has_many :wine_lists, dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :address, presence: true
  validates :proximity_radius_meters, numericality: { greater_than: 0 }

  # Fallback for owners who typed an address without picking an autocomplete
  # suggestion (picking one submits coordinates, so this never fires then).
  geocoded_by :address do |restaurant, results|
    result = results.find { |r| Geocoding.allowed_country?(r.data.dig("properties", "countrycode")) }
    if result
      restaurant.latitude = result.latitude
      restaurant.longitude = result.longitude
    end
  end
  after_validation :geocode_address, if: :needs_geocoding?

  scope :active, -> { where(active: true) }

  private

  def needs_geocoding?
    address.present? && address_changed? && latitude.blank?
  end

  # Geocoding is best-effort: coordinates stay nil on failure, never
  # blocking the save.
  def geocode_address
    geocode
  rescue StandardError => e
    Rails.logger.warn("Restaurant geocoding failed: #{e.class}: #{e.message}")
  end
end
```

- [ ] **Step 4: Run model + restaurant controller tests**

Run: `bin/rails test test/models/restaurant_test.rb test/integration/owner/restaurants_controller_test.rb`
Expected: PASS. The controller tests exercise create/update — the global empty-Photon stub from Task 1 keeps them hermetic even where they now trigger the fallback.

- [ ] **Step 5: Commit**

```bash
git add app/models/restaurant.rb test/models/restaurant_test.rb
git commit -m "feat: geocode restaurant address server-side when coordinates missing"
```

---

### Task 5: Frontend autocomplete on the owner restaurant form

**Files:**
- Modify: `config/importmap.rb` (via `bin/importmap pin`)
- Create: `vendor/javascript/stimulus-autocomplete.js` (via `bin/importmap pin`)
- Modify: `app/javascript/controllers/index.js`
- Create: `app/javascript/controllers/address_autocomplete_controller.js`
- Modify: `app/views/owner/restaurants/_form.html.erb`
- Modify: `app/assets/tailwind/application.css` (`@layer components`)
- Modify: `config/locales/en.yml` + `config/locales/it.yml` (remove now-unused `latitude:`/`longitude:` form keys, lines ~141-142 in both)
- Test: `test/system/owner_address_autocomplete_test.rb`

**Interfaces:**
- Consumes: `owner_address_suggestions_path` and the `<li role="option" data-autocomplete-value data-latitude data-longitude>` fragment shape from Task 3.
- Produces: the owner restaurant form submits `restaurant[latitude]`/`restaurant[longitude]` as hidden fields — filled by picking a suggestion, cleared by manual edits. No visible coordinate inputs remain.

- [ ] **Step 1: Pin stimulus-autocomplete**

Run: `bin/importmap pin stimulus-autocomplete`
Expected: `config/importmap.rb` gains `pin "stimulus-autocomplete" # @3.1.0` and `vendor/javascript/stimulus-autocomplete.js` is downloaded.

- [ ] **Step 2: Verify the vendored package's select event shape**

Run: `grep -n "autocomplete.change" vendor/javascript/stimulus-autocomplete.js`
Expected: the `CustomEvent("autocomplete.change", ...)` detail includes `selected` (the chosen `<li>` element). If — and only if — `selected` is absent in the vendored version, adapt `address_autocomplete_controller.js` (Step 4) to instead find the option by matching `event.detail.textValue` against `[role="option"]` elements' `data-autocomplete-value`; the rest of the plan is unchanged.

- [ ] **Step 3: Register the library controller**

Replace the contents of `app/javascript/controllers/index.js` with:

```js
// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { Autocomplete } from "stimulus-autocomplete"

eagerLoadControllersFrom("controllers", application)
application.register("autocomplete", Autocomplete)
```

- [ ] **Step 4: Write the companion Stimulus controller**

Create `app/javascript/controllers/address_autocomplete_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Companion to stimulus-autocomplete on the owner address field: copies the
// picked suggestion's coordinates into hidden latitude/longitude fields and
// clears them when the address is edited by hand — the server then
// re-geocodes on save (see Restaurant#geocode_address).
export default class extends Controller {
  static targets = ["latitude", "longitude"]

  select(event) {
    const selected = event.detail.selected
    if (!selected) return

    this.latitudeTarget.value = selected.dataset.latitude || ""
    this.longitudeTarget.value = selected.dataset.longitude || ""
  }

  clear() {
    this.latitudeTarget.value = ""
    this.longitudeTarget.value = ""
  }
}
```

(Programmatic value assignment by the library does not fire `input`, so `clear` only runs on real user edits.)

- [ ] **Step 5: Rewrite the address field and drop the visible coordinate inputs**

In `app/views/owner/restaurants/_form.html.erb`, replace the address `form-control` div (lines 18-21) AND the whole latitude/longitude `grid grid-cols-2 gap-4` div (lines 28-38) with this single block (in the address field's position; nothing remains where the grid was):

```erb
  <div class="form-control relative"
       data-controller="autocomplete address-autocomplete"
       data-autocomplete-url-value="<%= owner_address_suggestions_path %>"
       data-autocomplete-min-length-value="3"
       data-action="autocomplete.change->address-autocomplete#select">
    <%= f.label :address, t("owner.restaurants.form.address"), class: "label font-body text-xs uppercase tracking-wider text-base-content/60" %>
    <%= f.text_field :address, required: true, autocomplete: "off",
          class: "input input-bordered w-full font-body",
          placeholder: t("owner.restaurants.form.address_placeholder"),
          data: { autocomplete_target: "input", action: "input->address-autocomplete#clear" } %>
    <ul class="address-suggestions" data-autocomplete-target="results" hidden></ul>
    <%= f.hidden_field :latitude, data: { address_autocomplete_target: "latitude" } %>
    <%= f.hidden_field :longitude, data: { address_autocomplete_target: "longitude" } %>
  </div>
```

Remove the `latitude:` and `longitude:` keys from the `form:` sections of `config/locales/en.yml` and `config/locales/it.yml` (they are now unused; keep `proximity_radius` etc.).

- [ ] **Step 6: Style the dropdown with reusable component classes**

In `app/assets/tailwind/application.css`, inside the existing `@layer components` block (after the last component), add:

```css
  /* Address autocomplete dropdown (stimulus-autocomplete results) */
  .address-suggestions {
    @apply absolute left-0 right-0 top-full z-20 mt-1 list-none bg-base-100 border border-base-300 rounded-box shadow-lg p-1 max-h-64 overflow-y-auto;
  }

  .address-suggestion {
    @apply block px-3 py-2 rounded-field cursor-pointer text-sm font-body;
  }

  .address-suggestion:hover,
  .address-suggestion[aria-selected="true"],
  .address-suggestion.active {
    @apply bg-base-200;
  }

  .address-suggestion-attribution {
    @apply px-3 py-1 text-xs text-base-content/40 cursor-default;
  }
```

Run: `bin/rails tailwindcss:build`
Expected: completes without errors (new classes compiled).

- [ ] **Step 7: Write the system test**

Create `test/system/owner_address_autocomplete_test.rb`:

```ruby
require "application_system_test_case"

class OwnerAddressAutocompleteTest < ApplicationSystemTestCase
  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "My Restaurants", wait: 5
  end

  def visit_new_restaurant_form
    sign_in_as_owner
    click_link "Add Restaurant", match: :first
    assert_text "New Restaurant", wait: 5
  end

  test "form has hidden coordinate fields and no visible coordinate inputs" do
    visit_new_restaurant_form

    assert_selector "input[name='restaurant[latitude]']", visible: :hidden
    assert_selector "input[name='restaurant[longitude]']", visible: :hidden
    assert_no_selector "input[type='number'][name='restaurant[latitude]']"
    assert_no_text "Latitude"
  end

  test "picking a suggestion fills the hidden coordinates" do
    stub_photon([ photon_feature ])
    visit_new_restaurant_form

    fill_in "Address", with: "Via Roma 42"
    assert_selector "li[role='option']", text: "Via Roma 42, 20121 Milano, Italia", wait: 5
    find("li[role='option']", match: :first).click

    assert_equal "45.4642", find("input[name='restaurant[latitude]']", visible: false).value
    assert_equal "9.19", find("input[name='restaurant[longitude]']", visible: false).value
    assert_text "OpenStreetMap contributors"
  end

  test "editing the address after picking clears the coordinates" do
    stub_photon([ photon_feature ])
    visit_new_restaurant_form

    fill_in "Address", with: "Via Roma 42"
    assert_selector "li[role='option']", wait: 5
    find("li[role='option']", match: :first).click
    assert_equal "45.4642", find("input[name='restaurant[latitude]']", visible: false).value

    fill_in "Address", with: "Something else entirely"

    assert_equal "", find("input[name='restaurant[latitude]']", visible: false).value
    assert_equal "", find("input[name='restaurant[longitude]']", visible: false).value
  end
end
```

- [ ] **Step 8: Run the system tests**

Run: `bin/rails test:system TEST=test/system/owner_address_autocomplete_test.rb test/system/owner_restaurants_test.rb`
Expected: PASS (run once; a chromedriver-mismatch failure is environmental, not a regression). The existing restaurant creation test keeps passing — typing in Address now fires suggestion requests answered by the global empty stub.

- [ ] **Step 9: Commit**

```bash
git add config/importmap.rb vendor/javascript/stimulus-autocomplete.js app/javascript/controllers/index.js app/javascript/controllers/address_autocomplete_controller.js app/views/owner/restaurants/_form.html.erb app/assets/tailwind/application.css config/locales/en.yml config/locales/it.yml test/system/owner_address_autocomplete_test.rb
git commit -m "feat: address autocomplete with hidden coordinates on restaurant form"
```

---

### Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Rebuild assets**

Run: `bin/rails tailwindcss:build`
Expected: success (importmap JS needs no build step).

- [ ] **Step 2: Static checks**

Run: `bin/rubocop && bin/brakeman -q`
Expected: no offenses, no warnings. Fix anything reported before proceeding.

- [ ] **Step 3: Full test suite**

Run: `bin/rails test && bin/rails test:system`
Expected: all green, once each (do not loop on environmental chromedriver flakiness).

- [ ] **Step 4: Report**

Confirm every commit exists (`git log --oneline main..HEAD` shows 5 feature commits) and report completion. The pre-PR review pipeline (`/security-review`, `/postgres-patterns` — skippable here, no schema changes —, `/code-review`) runs next per the user's global workflow, before any PR is opened.
