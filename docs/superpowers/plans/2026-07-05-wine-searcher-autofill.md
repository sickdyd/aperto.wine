# Wine-Searcher Type-Ahead Autofill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Type-ahead wine-name suggestions in the owner wine form that autofill producer, region, grape variety, vintage year, and color from the Wine-Searcher API.

**Architecture:** A Stimulus controller debounces the name input and queries an authenticated JSON endpoint (`GET /owner/wine_lookups`), which proxies to `WineSearcher::Client` — the sole owner of HTTP, caching, and parsing concerns. No key configured → everything degrades to an inert no-op.

**Tech Stack:** Rails 8.1, Hotwire/Stimulus (importmap, eager-loaded controllers), Net::HTTP, Rails.cache, Minitest + WebMock, Capybara/Selenium system tests, DaisyUI/Tailwind.

**Spec:** `docs/superpowers/specs/2026-07-05-wine-searcher-autofill-design.md`

## Global Constraints

- Commit messages: conventional format (`feat:`, `test:`, …), NEVER any `Co-Authored-By` line.
- Before each commit: `bin/rubocop --force-exclusion`, `bin/brakeman -q`, and the affected tests must pass. (lefthook pre-commit also runs bundler-audit + brakeman.)
- Tests MUST NOT read `.env`/`.env.development` or call real external services. No real API key anywhere, including fixtures.
- The Wine-Searcher API key and base URL are secrets/config: `Rails.application.credentials.dig(:wine_searcher, …)` with `ENV` fallback. Never sent to the browser.
- **External-shape assumption (from spec):** the exact Wine-Searcher response schema is only visible with API access. Request params `api_key`, `winename`, `output=json` and the fixture shape below are documented assumptions; ALL parsing lives in `WineSearcher::Client#parse_results` so live verification (spec "Rollout" step 2) touches only that method and the fixtures.
- i18n: every user-visible string goes in both `config/locales/en.yml` and `config/locales/it.yml`.
- JS follows existing controller style (see `app/javascript/controllers/auto_submit_controller.js`): ES modules, no semicolon-free style changes, comment only non-obvious constraints.
- `db/schema.rb`, `db/cache_schema.rb`, `package-lock.json` must never appear in commits (no DB changes in this feature).

---

### Task 1: `WineSearcher::Client` — configuration, HTTP, parsing

**Files:**
- Modify: `Gemfile` (test group — add WebMock)
- Create: `app/services/wine_searcher/client.rb`
- Test: `test/services/wine_searcher/client_test.rb`

**Interfaces:**
- Produces: `WineSearcher::Result` — `Struct.new(:name, :producer, :region, :grape_variety, :vintage_year, :color, keyword_init: true)`.
- Produces: `WineSearcher::Client#search(query) => Array<WineSearcher::Result>` (never raises, `[]` on any failure) and `#configured? => Boolean`. Task 2 adds caching inside `#search`; Task 3 consumes both methods.

- [ ] **Step 1: Add WebMock to the test group**

In `Gemfile`, inside the existing `group :test do` block (the one containing `capybara`):

```ruby
  # Stub external HTTP in tests — no real network calls allowed
  gem "webmock"
```

Run: `bundle install`
Expected: `Bundle complete!` and `webmock` appears in `Gemfile.lock`.

- [ ] **Step 2: Write the failing client tests**

Create `test/services/wine_searcher/client_test.rb`:

```ruby
require "test_helper"
require "webmock/minitest"

module WineSearcher
  class ClientTest < ActiveSupport::TestCase
    API_URL = "https://api.example.test/wine-check"

    setup do
      ENV["WINE_SEARCHER_API_KEY"] = "test-key"
      ENV["WINE_SEARCHER_API_URL"] = API_URL
    end

    teardown do
      ENV.delete("WINE_SEARCHER_API_KEY")
      ENV.delete("WINE_SEARCHER_API_URL")
    end

    test "configured? is false without a key" do
      ENV.delete("WINE_SEARCHER_API_KEY")
      assert_not Client.new.configured?
    end

    test "configured? is true with key and url" do
      assert Client.new.configured?
    end

    test "search returns [] without calling the API when unconfigured" do
      ENV.delete("WINE_SEARCHER_API_KEY")
      results = Client.new.search("barolo")
      assert_equal [], results
      assert_not_requested :get, /api\.example\.test/
    end

    test "search returns [] for queries shorter than 3 chars without calling the API" do
      assert_equal [], Client.new.search("ba")
      assert_not_requested :get, /api\.example\.test/
    end

    test "search maps a wine payload to Result structs" do
      stub_request(:get, API_URL)
        .with(query: hash_including("api_key" => "test-key", "winename" => "haut brion"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            "wines" => [
              {
                "wine-name" => "Chateau Haut-Brion",
                "producer" => "Chateau Haut-Brion",
                "region" => "Pessac-Leognan",
                "grape" => "Cabernet Sauvignon blend",
                "vintage" => "1995",
                "wine-type" => "Red"
              }
            ]
          }.to_json
        )

      results = Client.new.search("Haut Brion")

      assert_equal 1, results.size
      result = results.first
      assert_equal "Chateau Haut-Brion", result.name
      assert_equal "Chateau Haut-Brion", result.producer
      assert_equal "Pessac-Leognan", result.region
      assert_equal "Cabernet Sauvignon blend", result.grape_variety
      assert_equal 1995, result.vintage_year
      assert_equal "red", result.color
    end

    test "search tolerates a single wine object instead of an array" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "gavi"))
        .to_return(status: 200, body: { "wine" => { "wine-name" => "Gavi di Gavi", "wine-type" => "White" } }.to_json)

      results = Client.new.search("gavi")
      assert_equal [ "Gavi di Gavi" ], results.map(&:name)
      assert_equal "white", results.first.color
    end

    test "search skips entries without a wine name and drops out-of-range vintages" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "mystery"))
        .to_return(status: 200, body: {
          "wines" => [
            { "region" => "Nowhere" },
            { "wine-name" => "Old One", "vintage" => "1400" },
            { "wine-name" => "Bad Year", "vintage" => "next year" }
          ]
        }.to_json)

      results = Client.new.search("mystery")
      assert_equal [ "Old One", "Bad Year" ], results.map(&:name)
      assert_nil results[0].vintage_year
      assert_nil results[1].vintage_year
    end

    test "color derivation handles all supported styles and unknown ones" do
      client = Client.new
      {
        "Red" => "red", "White" => "white", "Rose" => "rose", "Rosé" => "rose",
        "Sparkling" => "sparkling", "Champagne" => "sparkling",
        "Dessert" => "dessert", "Sweet white" => "dessert", "Port/Fortified" => "dessert",
        "Orange" => nil, nil => nil
      }.each do |style, expected|
        assert_equal expected, client.send(:derive_color, style), "style #{style.inspect}"
      end
    end

    test "search returns [] on non-200 responses" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo"))
        .to_return(status: 429, body: "quota exceeded")

      assert_equal [], Client.new.search("barolo")
    end

    test "search returns [] on timeouts" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo")).to_timeout

      assert_equal [], Client.new.search("barolo")
    end

    test "search returns [] on malformed JSON" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo"))
        .to_return(status: 200, body: "<not json>")

      assert_equal [], Client.new.search("barolo")
    end
  end
end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bin/rails test test/services/wine_searcher/client_test.rb`
Expected: FAIL — `NameError: uninitialized constant WineSearcher`.

- [ ] **Step 4: Implement the client**

Create `app/services/wine_searcher/client.rb`:

```ruby
module WineSearcher
  Result = Struct.new(:name, :producer, :region, :grape_variety, :vintage_year, :color, keyword_init: true)

  # Sole owner of Wine-Searcher HTTP concerns. Request params and the parsed
  # response shape follow the documented Wine Check API; the exact schema is
  # only visible with an API key, so all payload knowledge is confined to
  # parse_results/build_result (see spec "Rollout" step 2).
  class Client
    MIN_QUERY_LENGTH = 3
    OPEN_TIMEOUT_SECONDS = 2
    READ_TIMEOUT_SECONDS = 3
    VINTAGE_RANGE = (1900..).freeze

    # Ordered: more specific substrings before generic ones.
    COLOR_BY_STYLE = {
      "sparkling" => "sparkling", "champagne" => "sparkling",
      "dessert" => "dessert", "sweet" => "dessert", "fortified" => "dessert", "port" => "dessert",
      "rose" => "rose", "rosé" => "rose",
      "white" => "white", "red" => "red"
    }.freeze

    def configured?
      api_key.present? && api_url.present?
    end

    def search(query)
      normalized = query.to_s.strip
      return [] if normalized.length < MIN_QUERY_LENGTH || !configured?

      fetch_results(normalized)
    end

    private

    def api_key
      Rails.application.credentials.dig(:wine_searcher, :api_key).presence || ENV["WINE_SEARCHER_API_KEY"].presence
    end

    def api_url
      Rails.application.credentials.dig(:wine_searcher, :api_url).presence || ENV["WINE_SEARCHER_API_URL"].presence
    end

    def fetch_results(query)
      uri = URI.parse(api_url)
      uri.query = URI.encode_www_form(api_key: api_key, winename: query, output: "json")

      response = perform_request(uri)
      unless response.is_a?(Net::HTTPOK)
        Rails.logger.warn("[wine_searcher] non-200 response: #{response.code}")
        return []
      end

      parse_results(JSON.parse(response.body))
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
           SocketError, SystemCallError, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      Rails.logger.warn("[wine_searcher] search failed: #{e.class}: #{e.message}")
      []
    end

    def perform_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT_SECONDS
      http.read_timeout = READ_TIMEOUT_SECONDS
      http.get(uri.request_uri, "User-Agent" => "aperto.wine")
    end

    def parse_results(payload)
      wines = payload["wines"] || payload["wine"]
      Array.wrap(wines).filter_map { |entry| build_result(entry) }
    end

    def build_result(entry)
      return nil unless entry.is_a?(Hash)

      name = entry["wine-name"].presence
      return nil unless name

      Result.new(
        name: name,
        producer: entry["producer"].presence,
        region: entry["region"].presence,
        grape_variety: entry["grape"].presence,
        vintage_year: parse_vintage(entry["vintage"]),
        color: derive_color(entry["wine-type"] || entry["style"])
      )
    end

    def parse_vintage(value)
      year = Integer(value.to_s, exception: false)
      year if year && VINTAGE_RANGE.cover?(year) && year <= Date.current.year
    end

    def derive_color(style)
      normalized = style.to_s.downcase
      return nil if normalized.blank?

      COLOR_BY_STYLE.find { |fragment, _| normalized.include?(fragment) }&.last
    end
  end
end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/services/wine_searcher/client_test.rb`
Expected: PASS — 11 runs, 0 failures, 0 errors.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop --force-exclusion app/services test/services Gemfile
git add Gemfile Gemfile.lock app/services/wine_searcher/client.rb test/services/wine_searcher/client_test.rb
git commit -m "feat: add WineSearcher::Client with defensive parsing"
```

---

### Task 2: Client caching (24h TTL, negative caching)

**Files:**
- Modify: `app/services/wine_searcher/client.rb`
- Test: `test/services/wine_searcher/client_test.rb`

**Interfaces:**
- Consumes: Task 1's `Client#search`.
- Produces: same signature; adds `Rails.cache` fetch keyed `wine_searcher/v1/<downcased query>`, `expires_in: 24.hours`, caching `[]` results too. Struct values are cached (Result is a Struct — safe to marshal).

- [ ] **Step 1: Write the failing caching tests**

Append inside `WineSearcher::ClientTest` (before the final `end end`):

```ruby
    test "search caches results for identical normalized queries" do
      with_memory_cache do
        stub = stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo"))
          .to_return(status: 200, body: { "wines" => [ { "wine-name" => "Barolo" } ] }.to_json)

        first = Client.new.search("Barolo")
        second = Client.new.search("  barolo ")

        assert_equal first, second
        assert_requested stub, times: 1
      end
    end

    test "search caches empty result sets (negative caching)" do
      with_memory_cache do
        stub = stub_request(:get, API_URL).with(query: hash_including("winename" => "nonexistent"))
          .to_return(status: 200, body: { "wines" => [] }.to_json)

        assert_equal [], Client.new.search("nonexistent")
        assert_equal [], Client.new.search("nonexistent")
        assert_requested stub, times: 1
      end
    end

    test "failures are not cached" do
      with_memory_cache do
        stub_request(:get, API_URL).with(query: hash_including("winename" => "flaky"))
          .to_timeout.then
          .to_return(status: 200, body: { "wines" => [ { "wine-name" => "Flaky Estate" } ] }.to_json)

        assert_equal [], Client.new.search("flaky")
        assert_equal [ "Flaky Estate" ], Client.new.search("flaky").map(&:name)
      end
    end

    private

    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bin/rails test test/services/wine_searcher/client_test.rb`
Expected: the two cache-hit tests FAIL with `expected 1 time, made 2 times` (the null store in test env never caches); "failures are not cached" passes incidentally.

- [ ] **Step 3: Implement caching in the client**

In `app/services/wine_searcher/client.rb`, add the constant below the timeouts:

```ruby
    CACHE_TTL = 24.hours
    CACHE_NAMESPACE = "wine_searcher/v1".freeze
```

Replace `#search` with:

```ruby
    def search(query)
      normalized = query.to_s.strip
      return [] if normalized.length < MIN_QUERY_LENGTH || !configured?

      cache_key = "#{CACHE_NAMESPACE}/#{normalized.downcase}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      fetch_results(normalized).tap do |results|
        # A failed upstream call returns [] via the rescue in fetch_results and
        # must stay uncached so the next keystroke can retry; a genuine empty
        # result set IS cached (negative caching) to protect the daily quota.
        Rails.cache.write(cache_key, results, expires_in: CACHE_TTL) unless results.equal?(FAILURE)
      end
    end
```

Distinguish "failed" from "empty": add above `#search`:

```ruby
    # Sentinel: rescue paths return this exact frozen array so search can tell
    # "upstream failed" (don't cache) from "no matches" (cache it).
    FAILURE = [].freeze
```

In `fetch_results`, change the two `[]` returns (non-200 branch and rescue) to `FAILURE`, and change `search`'s early return `[]` to stay `[]` as-is. `search` returns `FAILURE` to callers unchanged — it's still an empty array to them.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/wine_searcher/client_test.rb`
Expected: PASS — 14 runs, 0 failures, 0 errors.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop --force-exclusion app/services test/services
git add app/services/wine_searcher/client.rb test/services/wine_searcher/client_test.rb
git commit -m "feat: cache Wine-Searcher lookups for 24h with negative caching"
```

---

### Task 3: `Owner::WineLookupsController` + route

**Files:**
- Modify: `config/routes.rb` (inside `namespace :owner`)
- Create: `app/controllers/owner/wine_lookups_controller.rb`
- Test: `test/integration/owner/wine_lookups_controller_test.rb`

**Interfaces:**
- Consumes: `WineSearcher::Client#search` / `#configured?` (Tasks 1-2).
- Produces: `GET /owner/wine_lookups?q=<query>` (helper `owner_wine_lookups_path`) → JSON `[{"name":…,"producer":…,"region":…,"grape_variety":…,"vintage_year":…,"color":…}]`. Task 4's Stimulus controller consumes this exact shape.

- [ ] **Step 1: Write the failing controller tests**

Create `test/integration/owner/wine_lookups_controller_test.rb`:

```ruby
require "test_helper"
require "webmock/minitest"

module Owner
  class WineLookupsControllerTest < ActionDispatch::IntegrationTest
    API_URL = "https://api.example.test/wine-check"

    setup do
      ENV["WINE_SEARCHER_API_KEY"] = "test-key"
      ENV["WINE_SEARCHER_API_URL"] = API_URL
    end

    teardown do
      ENV.delete("WINE_SEARCHER_API_KEY")
      ENV.delete("WINE_SEARCHER_API_URL")
    end

    test "requires authentication" do
      get owner_wine_lookups_path(q: "barolo")
      assert_redirected_to sign_in_path
    end

    test "requires owner role" do
      sign_in_as users(:customer)
      get owner_wine_lookups_path(q: "barolo")
      assert_response :redirect
    end

    test "returns mapped results as JSON" do
      stub_request(:get, API_URL).with(query: hash_including("winename" => "barolo"))
        .to_return(status: 200, body: {
          "wines" => [ { "wine-name" => "Barolo Riserva", "region" => "Piemonte", "grape" => "Nebbiolo",
                         "vintage" => "2018", "wine-type" => "Red" } ]
        }.to_json)

      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "barolo")

      assert_response :success
      payload = JSON.parse(response.body)
      assert_equal 1, payload.size
      assert_equal(
        { "name" => "Barolo Riserva", "producer" => nil, "region" => "Piemonte",
          "grape_variety" => "Nebbiolo", "vintage_year" => 2018, "color" => "red" },
        payload.first
      )
    end

    test "returns [] for short queries without calling the API" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "ba")

      assert_response :success
      assert_equal [], JSON.parse(response.body)
      assert_not_requested :get, /api\.example\.test/
    end

    test "returns [] for overlong queries without calling the API" do
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "a" * 101)

      assert_response :success
      assert_equal [], JSON.parse(response.body)
      assert_not_requested :get, /api\.example\.test/
    end

    test "returns [] when no API key is configured" do
      ENV.delete("WINE_SEARCHER_API_KEY")
      sign_in_as users(:owner)
      get owner_wine_lookups_path(q: "barolo")

      assert_response :success
      assert_equal [], JSON.parse(response.body)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/owner/wine_lookups_controller_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'owner_wine_lookups_path'`.

- [ ] **Step 3: Add route and controller**

In `config/routes.rb`, inside `namespace :owner do`, directly above `resources :restaurants do`:

```ruby
    # Wine data autofill proxy — not nested under restaurants: wine reference
    # data is global, only the session needs to be an owner.
    resources :wine_lookups, only: [ :index ]
```

Create `app/controllers/owner/wine_lookups_controller.rb`:

```ruby
module Owner
  class WineLookupsController < BaseController
    # JSON-only endpoint: the sidebar query is wasted work here.
    skip_before_action :set_sidebar_restaurants

    # Second guard on the upstream daily quota (client cache is the first).
    # Declarative framework behavior — exercised manually, not unit-tested
    # (Rails.cache is a null store in test, so the limiter never trips there).
    rate_limit to: 30, within: 1.minute, only: :index,
               with: -> { render json: [], status: :too_many_requests }

    QUERY_LENGTH_RANGE = (3..100)

    def index
      query = params[:q].to_s.strip
      return render json: [] unless QUERY_LENGTH_RANGE.cover?(query.length)

      render json: WineSearcher::Client.new.search(query).map(&:to_h)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/integration/owner/wine_lookups_controller_test.rb`
Expected: PASS — 6 runs, 0 failures, 0 errors.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop --force-exclusion app/controllers config test/integration
bin/brakeman -q --no-pager
git add config/routes.rb app/controllers/owner/wine_lookups_controller.rb test/integration/owner/wine_lookups_controller_test.rb
git commit -m "feat: add owner wine lookup proxy endpoint"
```

---

### Task 4: Stimulus autofill controller, form wiring, i18n, system test

**Files:**
- Create: `app/javascript/controllers/wine_autofill_controller.js`
- Modify: `app/views/owner/wines/_form.html.erb` (basic-info fieldset)
- Modify: `config/locales/en.yml`, `config/locales/it.yml` (under `owner.wines`)
- Test: `test/system/wine_autofill_test.rb`

**Interfaces:**
- Consumes: Task 3's endpoint via `data-wine-autofill-url-value` and JSON keys `name`, `producer`, `region`, `grape_variety`, `vintage_year`, `color`.
- Produces: Stimulus identifier `wine-autofill`; targets `input`, `results`, `producer`, `grape`, `vintage`, `region`, `color`.

- [ ] **Step 1: Write the failing system test**

Create `test/system/wine_autofill_test.rb`:

```ruby
require "application_system_test_case"
require "webmock/minitest"

# System tests only talk to localhost (Capybara server + chromedriver), so
# blocking external HTTP here is safe and guarantees no test can leak a real
# Wine-Searcher call.
WebMock.disable_net_connect!(allow_localhost: true)

class WineAutofillTest < ApplicationSystemTestCase
  API_URL = "https://api.example.test/wine-check"

  setup do
    ENV["WINE_SEARCHER_API_KEY"] = "test-key"
    ENV["WINE_SEARCHER_API_URL"] = API_URL

    stub_request(:get, API_URL).with(query: hash_including("winename" => "sassicaia"))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "wines" => [ { "wine-name" => "Sassicaia", "producer" => "Tenuta San Guido",
                       "region" => "Toscana", "grape" => "Cabernet Sauvignon",
                       "vintage" => "2019", "wine-type" => "Red" } ]
      }.to_json)
  end

  teardown do
    ENV.delete("WINE_SEARCHER_API_KEY")
    ENV.delete("WINE_SEARCHER_API_URL")
  end

  def sign_in_as_owner
    user = users(:owner)
    visit sign_in_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    find("input[type='submit']").click
    assert_text "My Restaurants", wait: 5
  end

  test "selecting a suggestion fills the descriptive fields" do
    sign_in_as_owner
    visit new_owner_restaurant_wine_path(restaurant_id: restaurants(:osteria))

    fill_in "wine[name]", with: "sassicaia"
    assert_text "Sassicaia — Toscana", wait: 5

    find("[data-wine-autofill-target='results'] button", match: :first).click

    assert_field "wine[name]", with: "Sassicaia"
    assert_field "wine[producer]", with: "Tenuta San Guido"
    assert_field "wine[grape_variety]", with: "Cabernet Sauvignon"
    assert_field "wine[vintage_year]", with: "2019"
    assert_field "wine[region]", with: "Toscana"
    assert_equal "red", find("select[name='wine[color]']").value
  end

  test "keyboard-only: arrow down and enter selects, escape closes" do
    sign_in_as_owner
    visit new_owner_restaurant_wine_path(restaurant_id: restaurants(:osteria))

    fill_in "wine[name]", with: "sassicaia"
    assert_text "Sassicaia — Toscana", wait: 5

    name_input = find("input[name='wine[name]']")
    name_input.send_keys :escape
    assert_no_text "Sassicaia — Toscana"

    # Re-open and select with keyboard only
    name_input.send_keys " "
    name_input.send_keys :backspace
    assert_text "Sassicaia — Toscana", wait: 5
    name_input.send_keys :arrow_down
    name_input.send_keys :enter

    assert_field "wine[producer]", with: "Tenuta San Guido"
    assert_field "wine[region]", with: "Toscana"
  end
end
```

- [ ] **Step 2: Run the system test to verify it fails**

Run: `bin/rails test:system TEST=test/system/wine_autofill_test.rb`
Expected: FAIL — no dropdown appears (`assert_text "Sassicaia — Toscana"` times out). Chromedriver flakiness note: retries are automatic via minitest-retry; a consistent failure is real.

- [ ] **Step 3: Implement the Stimulus controller**

Create `app/javascript/controllers/wine_autofill_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Type-ahead on the wine name field. Queries the owner wine_lookups proxy and
// fills the descriptive fields when the owner picks a suggestion. Any fetch
// problem simply leaves the dropdown closed — manual entry must never break.
export default class extends Controller {
  static targets = ["input", "results", "producer", "grape", "vintage", "region", "color"]
  static values = { url: String, minChars: { type: Number, default: 3 }, delay: { type: Number, default: 350 } }

  disconnect() {
    this.#reset()
  }

  search() {
    clearTimeout(this.timeout)
    const query = this.inputTarget.value.trim()
    if (query.length < this.minCharsValue) {
      this.#close()
      return
    }
    this.timeout = setTimeout(() => this.#fetchSuggestions(query), this.delayValue)
  }

  close(event) {
    // Keep the dropdown open when focus moves into one of its buttons.
    if (event?.relatedTarget && this.resultsTarget.contains(event.relatedTarget)) return
    this.#close()
  }

  navigate(event) {
    const buttons = this.#suggestionButtons()
    if (buttons.length === 0) return

    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp": {
        event.preventDefault()
        const step = event.key === "ArrowDown" ? 1 : -1
        const next = (this.activeIndex + step + buttons.length) % buttons.length
        this.#highlight(buttons, next)
        break
      }
      case "Enter":
        if (this.activeIndex >= 0) {
          event.preventDefault()
          buttons[this.activeIndex].click()
        }
        break
      case "Escape":
        this.#close()
        break
    }
  }

  select(event) {
    const wine = JSON.parse(event.currentTarget.dataset.wine)
    this.inputTarget.value = wine.name
    this.#fill(this.producerTarget, wine.producer)
    this.#fill(this.grapeTarget, wine.grape_variety)
    this.#fill(this.vintageTarget, wine.vintage_year)
    this.#fill(this.regionTarget, wine.region)
    if (wine.color) this.colorTarget.value = wine.color
    this.#close()
    this.inputTarget.focus()
  }

  async #fetchSuggestions(query) {
    this.abortController?.abort()
    this.abortController = new AbortController()

    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal
      })
      if (!response.ok) {
        this.#close()
        return
      }
      this.#render(await response.json())
    } catch (error) {
      if (error.name !== "AbortError") this.#close()
    }
  }

  #render(wines) {
    if (wines.length === 0) {
      this.#close()
      return
    }
    const items = wines.map((wine) => {
      const label = [wine.name, wine.region].filter(Boolean).join(" — ")
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "w-full text-left px-4 py-2 hover:bg-base-200 font-body text-sm"
      button.textContent = label
      button.dataset.wine = JSON.stringify(wine)
      button.dataset.action = "wine-autofill#select"
      item.appendChild(button)
      return item
    })
    this.resultsTarget.replaceChildren(...items)
    this.resultsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.activeIndex = -1
  }

  #suggestionButtons() {
    return Array.from(this.resultsTarget.querySelectorAll("button"))
  }

  #highlight(buttons, index) {
    buttons.forEach((button, i) => button.classList.toggle("bg-base-200", i === index))
    this.activeIndex = index
  }

  #fill(target, value) {
    if (value !== null && value !== undefined && value !== "") target.value = value
  }

  #close() {
    this.resultsTarget.replaceChildren()
    this.resultsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.activeIndex = -1
  }

  #reset() {
    clearTimeout(this.timeout)
    this.abortController?.abort()
  }
}
```

- [ ] **Step 4: Wire the form**

In `app/views/owner/wines/_form.html.erb`:

1. Add the controller to the form element — change the opening line to:

```erb
<%= form_with model: [:owner, @restaurant, wine], class: "space-y-6 max-w-2xl",
      data: { controller: "wine-autofill", wine_autofill_url_value: owner_wine_lookups_path } do |f| %>
```

2. Replace the name form-control div with (dropdown needs a positioning context; combobox ARIA on the input):

```erb
    <div class="form-control relative">
      <%= f.label :name, t("owner.wines.form.name"), class: "label font-body text-xs uppercase tracking-wider text-base-content/60" %>
      <%= f.text_field :name, required: true, autocomplete: "off",
            class: "input input-bordered w-full font-body",
            placeholder: t("owner.wines.form.name_placeholder"),
            role: "combobox", "aria-expanded": "false", "aria-autocomplete": "list",
            "aria-label": t("owner.wines.autofill.aria_label"),
            data: {
              wine_autofill_target: "input",
              action: "input->wine-autofill#search keydown->wine-autofill#navigate blur->wine-autofill#close"
            } %>
      <ul class="hidden absolute top-full left-0 right-0 z-20 mt-1 menu p-0 bg-base-100 border border-base-300 rounded-box shadow-lg max-h-64 overflow-y-auto"
          role="listbox"
          data-wine-autofill-target="results"></ul>
    </div>
```

3. Add targets to the four other inputs (keep every existing attribute, add the `data`):
   - producer: `data: { wine_autofill_target: "producer" }`
   - grape_variety: `data: { wine_autofill_target: "grape" }`
   - color select: `{}` options hash gains nothing; add to the html options: `data: { wine_autofill_target: "color" }`
   - vintage_year: `data: { wine_autofill_target: "vintage" }`
   - region: `data: { wine_autofill_target: "region" }`

- [ ] **Step 5: Add i18n strings**

In `config/locales/en.yml` under `owner: wines:` (sibling of `form:`):

```yaml
      autofill:
        aria_label: Wine name with autocomplete suggestions
```

In `config/locales/it.yml`, same position:

```yaml
      autofill:
        aria_label: Nome del vino con suggerimenti automatici
```

(No visible copy is added — the dropdown renders API data only, and an empty result set closes the list rather than showing a "no results" row. YAGNI until UX asks for it.)

- [ ] **Step 6: Run the system test to verify it passes**

Run: `bin/rails test:system TEST=test/system/wine_autofill_test.rb`
Expected: PASS — 2 runs, 0 failures, 0 errors.

- [ ] **Step 7: Lint and commit**

```bash
bin/rubocop --force-exclusion
git add app/javascript/controllers/wine_autofill_controller.js app/views/owner/wines/_form.html.erb config/locales/en.yml config/locales/it.yml test/system/wine_autofill_test.rb
git commit -m "feat: type-ahead Wine-Searcher autofill in owner wine form"
```

---

### Task 5: Full verification

**Files:** none created — verification only.

- [ ] **Step 1: Full unit/integration suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors (219+ runs).

- [ ] **Step 2: Full system suite**

Run: `bin/rails test:system`
Expected: 0 failures, 0 errors. (Known environment flakiness: chromedriver mismatch — a retry via minitest-retry is normal; consistent failures are real.)

- [ ] **Step 3: Static checks**

Run: `bin/rubocop --force-exclusion && bin/brakeman -q --no-pager`
Expected: no offenses (ignore pre-existing `db/*schema.rb` noise if rubocop is run without exclusions), no brakeman warnings.

- [ ] **Step 4: Confirm clean diff hygiene**

Run: `git status --short`
Expected: empty (no stray `package-lock.json` / schema changes staged or unstaged).

---

## Post-plan (not tasks — session-level workflow)

Per user global rules, before the PR: run `/security-review`, then `/code-review` (skip `/postgres-patterns` — no DB changes); apply CRITICAL/HIGH findings; push branch; open PR with test plan. Rollout steps (credentials, live schema verification) are in the spec.
