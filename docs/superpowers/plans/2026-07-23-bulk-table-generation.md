# Bulk Table Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let restaurant owners generate all their tables in one go (floors × tables per floor, with a naming pattern), so every table immediately has a QR code, printable via the existing bulk-print sheet.

**Architecture:** A `TableBulkGeneration` ActiveModel form object (no DB table) validates the grid parameters and creates `RestaurantTable` rows in a transaction, skipping names that already exist. Two new collection actions on `Owner::RestaurantTablesController` (`bulk_new` / `bulk_create`) render the form and run it. Floors map onto the existing `area` column (e.g. "Piano 1", "Piano 2"), so the grouped index and the existing `bulk_print` (all / per-area) work unchanged. Manual rename stays the existing `edit` action.

**Tech Stack:** Rails 8, ActiveModel::Model + ActiveModel::Attributes, Minitest fixtures, daisyUI 5, i18n (en + it).

## Global Constraints

- NO migration needed — reuses `restaurant_tables` (name, area, position, active, token).
- Every user-facing string must exist in BOTH `config/locales/en.yml` and `config/locales/it.yml` under `owner.tables.bulk.*` (plus `activemodel.attributes.table_bulk_generation.*`).
- Forms use the daisyUI 5 field markup from commit 914bfbd: wrapper `div.field`, labels `class="field-label"`, inputs `class="input w-full font-body"`, sections `fieldset.form-section`, actions `div.form-actions`, submit `class="btn-wine"` (see `app/views/owner/restaurant_tables/_form.html.erb` as reference).
- The route resource is `resources :tables, controller: "restaurant_tables"` — path helpers are `*_owner_restaurant_tables_path` style; `form_with` needs explicit `url:` + `scope:`.
- NEVER add `Co-Authored-By` or any Claude/Anthropic reference to commits.
- Run tests with `bin/rails test <file>` (unit/integration) and `bin/rails test:system` only where the task says so. Run each suite once; failures mentioning chromedriver are environmental, not regressions.
- Caps: max 10 floors, max 100 tables per floor, max 200 tables per generation.

---

### Task 1: `TableBulkGeneration` form object

**Files:**
- Create: `app/models/table_bulk_generation.rb`
- Modify: `config/locales/en.yml` (inside `owner: tables:` add `bulk:` subtree; top-level `activemodel:` key)
- Modify: `config/locales/it.yml` (same keys, Italian)
- Test: `test/models/table_bulk_generation_test.rb`

**Interfaces:**
- Consumes: `RestaurantTable` model (validations: name presence/uniqueness scoped to `[restaurant_id, area]` case-insensitive; `has_secure_token`), `restaurants` fixtures (use the same fixture the existing `test/models/restaurant_table_test.rb` uses).
- Produces: `TableBulkGeneration.new(restaurant:, floors_count:, tables_per_floor:, floor_label:, name_pattern:)`; `#save → true/false`; readers `#created_count`, `#skipped_count`; constants `NAME_PATTERNS` (`%w[table_number t_number number_only floor_table]`), `MAX_FLOORS = 10`, `MAX_TABLES_PER_FLOOR = 100`, `MAX_TOTAL = 200`.

- [ ] **Step 1: Write the failing tests**

`test/models/table_bulk_generation_test.rb` — mirror the setup style of `test/models/restaurant_table_test.rb` (same fixture accessor for the restaurant). Test cases:

```ruby
require "test_helper"

class TableBulkGenerationTest < ActiveSupport::TestCase
  # Use the same restaurant fixture as restaurant_table_test.rb.
  # IMPORTANT: check test/fixtures/restaurant_tables.yml — pick a restaurant
  # whose existing fixture tables don't collide, or clear them in setup with
  # restaurant.restaurant_tables.delete_all for deterministic counts.
  setup do
    @restaurant = restaurants(:one) # adjust to actual fixture name
    @restaurant.restaurant_tables.delete_all
  end

  test "generates floors × tables with localized table-word pattern" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 2, tables_per_floor: 3,
                                  floor_label: "Floor", name_pattern: "table_number")
    assert gen.save
    assert_equal 6, gen.created_count
    assert_equal 0, gen.skipped_count
    areas = @restaurant.restaurant_tables.distinct.pluck(:area).sort
    assert_equal [ "Floor 1", "Floor 2" ], areas
    floor1 = @restaurant.restaurant_tables.where(area: "Floor 1").order(:position)
    assert_equal [ "#{I18n.t('owner.tables.bulk.table_word')} 1",
                   "#{I18n.t('owner.tables.bulk.table_word')} 2",
                   "#{I18n.t('owner.tables.bulk.table_word')} 3" ], floor1.map(&:name)
    assert_equal [ 1, 2, 3 ], floor1.map(&:position)
    assert floor1.all?(&:active?)
    assert floor1.all? { |t| t.token.present? }
  end

  test "single floor with blank label leaves area nil" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 2,
                                  floor_label: "", name_pattern: "number_only")
    assert gen.save
    assert_equal [ nil ], @restaurant.restaurant_tables.distinct.pluck(:area)
    assert_equal [ "1", "2" ], @restaurant.restaurant_tables.order(:position).map(&:name)
  end

  test "single floor with label uses label verbatim as area" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 1,
                                  floor_label: "Terrazza", name_pattern: "t_number")
    assert gen.save
    table = @restaurant.restaurant_tables.sole
    assert_equal "Terrazza", table.area
    assert_equal "T1", table.name
  end

  test "floor_table pattern names tables floor-number" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 2, tables_per_floor: 2,
                                  floor_label: "Piano", name_pattern: "floor_table")
    assert gen.save
    assert_equal [ "1-1", "1-2" ], @restaurant.restaurant_tables.where(area: "Piano 1").order(:position).map(&:name)
    assert_equal [ "2-1", "2-2" ], @restaurant.restaurant_tables.where(area: "Piano 2").order(:position).map(&:name)
  end

  test "skips tables whose name already exists in the same area (case-insensitive)" do
    @restaurant.restaurant_tables.create!(name: "t1", area: "Sala", active: true)
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 2,
                                  floor_label: "Sala", name_pattern: "t_number")
    assert gen.save
    assert_equal 1, gen.created_count
    assert_equal 1, gen.skipped_count
    assert_equal 2, @restaurant.restaurant_tables.count
  end

  test "requires floor_label when more than one floor" do
    gen = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 2, tables_per_floor: 2,
                                  floor_label: "  ", name_pattern: "t_number")
    assert_not gen.save
    assert gen.errors[:floor_label].any?
    assert_equal 0, @restaurant.restaurant_tables.count
  end

  test "rejects out-of-range counts, unknown patterns, and totals over the cap" do
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 0, tables_per_floor: 5, name_pattern: "t_number").save
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 11, tables_per_floor: 5, floor_label: "F", name_pattern: "t_number").save
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 101, name_pattern: "t_number").save
    assert_not TableBulkGeneration.new(restaurant: @restaurant, floors_count: 1, tables_per_floor: 5, name_pattern: "evil").save
    over_cap = TableBulkGeneration.new(restaurant: @restaurant, floors_count: 3, tables_per_floor: 100, floor_label: "F", name_pattern: "t_number")
    assert_not over_cap.save
    assert over_cap.errors[:base].any?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/table_bulk_generation_test.rb`
Expected: FAIL (uninitialized constant TableBulkGeneration)

- [ ] **Step 3: Implement the form object**

`app/models/table_bulk_generation.rb`:

```ruby
# Form object that creates a batch of RestaurantTables from a floors ×
# tables-per-floor grid. Floors become the `area` grouping; names follow a
# selected pattern; existing names in the same area are skipped, not errors.
class TableBulkGeneration
  include ActiveModel::Model
  include ActiveModel::Attributes

  NAME_PATTERNS = %w[table_number t_number number_only floor_table].freeze
  MAX_FLOORS = 10
  MAX_TABLES_PER_FLOOR = 100
  MAX_TOTAL = 200

  attribute :floors_count, :integer, default: 1
  attribute :tables_per_floor, :integer, default: 10
  attribute :floor_label, :string
  attribute :name_pattern, :string, default: "table_number"

  attr_accessor :restaurant
  attr_reader :created_count, :skipped_count

  validates :floors_count, numericality: { only_integer: true, in: 1..MAX_FLOORS }
  validates :tables_per_floor, numericality: { only_integer: true, in: 1..MAX_TABLES_PER_FLOOR }
  validates :name_pattern, inclusion: { in: NAME_PATTERNS }
  validate :floor_label_required_for_multiple_floors
  validate :total_within_cap

  def save
    return false unless valid?

    existing = restaurant.restaurant_tables.pluck(:area, :name)
                         .map { |area, name| [ area, name.downcase ] }.to_set
    @created_count = 0
    @skipped_count = 0

    RestaurantTable.transaction do
      each_table do |area, name, position|
        if existing.include?([ area, name.downcase ])
          @skipped_count += 1
        else
          restaurant.restaurant_tables.create!(name:, area:, position:, active: true)
          @created_count += 1
        end
      end
    end
    true
  end

  private

  def each_table
    (1..floors_count).each do |floor|
      (1..tables_per_floor).each do |number|
        yield area_for(floor), name_for(floor, number), number
      end
    end
  end

  def area_for(floor)
    label = floor_label.to_s.strip
    return nil if label.blank?

    floors_count > 1 ? "#{label} #{floor}" : label
  end

  def name_for(floor, number)
    case name_pattern
    when "table_number" then "#{I18n.t('owner.tables.bulk.table_word')} #{number}"
    when "t_number" then "T#{number}"
    when "number_only" then number.to_s
    when "floor_table" then "#{floor}-#{number}"
    end
  end

  def floor_label_required_for_multiple_floors
    return if floors_count.to_i <= 1 || floor_label.to_s.strip.present?

    errors.add(:floor_label, :blank)
  end

  def total_within_cap
    return unless floors_count.to_i >= 1 && tables_per_floor.to_i >= 1
    return if floors_count * tables_per_floor <= MAX_TOTAL

    errors.add(:base, I18n.t("owner.tables.bulk.too_many", max: MAX_TOTAL))
  end
end
```

Locales — in `config/locales/en.yml`, inside the existing `owner: → tables:` section add (keep alphabetical-ish placement near the `form:` key):

```yaml
      bulk:
        table_word: "Table"
        floor_default: "Floor"
        too_many: "You can generate at most %{max} tables at once."
```

In `config/locales/it.yml` (same nesting):

```yaml
      bulk:
        table_word: "Tavolo"
        floor_default: "Piano"
        too_many: "Puoi generare al massimo %{max} tavoli alla volta."
```

Also add top-level `activemodel:` translations to BOTH files (check first whether a top-level `activemodel:` or `activerecord:` key already exists and merge instead of duplicating):

```yaml
  activemodel:
    attributes:
      table_bulk_generation:
        floors_count: "Floors"            # it: "Piani"
        tables_per_floor: "Tables per floor"  # it: "Tavoli per piano"
        floor_label: "Floor name"         # it: "Nome del piano"
        name_pattern: "Table naming"      # it: "Nome dei tavoli"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/table_bulk_generation_test.rb`
Expected: PASS (7 tests). Also run `bin/rails test test/models/restaurant_table_test.rb` — still PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/table_bulk_generation.rb test/models/table_bulk_generation_test.rb config/locales/en.yml config/locales/it.yml
git commit -m "feat: TableBulkGeneration form object for floors × tables generation"
```

---

### Task 2: Routes + controller actions

**Files:**
- Modify: `config/routes.rb` (tables collection block, ~line 44)
- Modify: `app/controllers/owner/restaurant_tables_controller.rb`
- Modify: `config/locales/en.yml` + `config/locales/it.yml` (flash messages)
- Test: `test/integration/owner/restaurant_tables_controller_test.rb` (append tests)

**Interfaces:**
- Consumes: `TableBulkGeneration` from Task 1 (`.new(restaurant:, **attrs)`, `#save`, `#created_count`, `#skipped_count`).
- Produces: `GET bulk_new_owner_restaurant_tables_path(@restaurant)` renders `@generation`; `POST bulk_create_owner_restaurant_tables_path(@restaurant)` with `params[:table_bulk_generation]` → redirect to index (303) with notice, or 422 re-render. Task 3's view is `app/views/owner/restaurant_tables/bulk_new.html.erb` using `@generation`.

- [ ] **Step 1: Write the failing integration tests**

Append to `test/integration/owner/restaurant_tables_controller_test.rb`, matching its existing sign-in helper/fixture conventions (read the file first; reuse its setup — owner user, other-user restaurant for the scoping test):

```ruby
  test "bulk_new renders the generation form" do
    get bulk_new_owner_restaurant_tables_path(@restaurant)
    assert_response :success
  end

  test "bulk_create generates tables and redirects with notice" do
    assert_difference -> { @restaurant.restaurant_tables.count }, 4 do
      post bulk_create_owner_restaurant_tables_path(@restaurant), params: {
        table_bulk_generation: { floors_count: 2, tables_per_floor: 2,
                                 floor_label: "Piano", name_pattern: "t_number" }
      }
    end
    assert_redirected_to owner_restaurant_tables_path(@restaurant)
    assert_equal 303, response.status
  end

  test "bulk_create re-renders with 422 on invalid input" do
    assert_no_difference -> { @restaurant.restaurant_tables.count } do
      post bulk_create_owner_restaurant_tables_path(@restaurant), params: {
        table_bulk_generation: { floors_count: 0, tables_per_floor: 2, name_pattern: "t_number" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "bulk actions are scoped to the owner's restaurants" do
    get bulk_new_owner_restaurant_tables_path(@other_restaurant)
    assert_response :not_found
    post bulk_create_owner_restaurant_tables_path(@other_restaurant), params: {
      table_bulk_generation: { floors_count: 1, tables_per_floor: 1, name_pattern: "t_number" }
    }
    assert_response :not_found
  end
```

(Adjust `@restaurant` / `@other_restaurant` / sign-in to whatever the file already uses — the existing tests there show the pattern, including how not-found is asserted for foreign restaurants.)

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/owner/restaurant_tables_controller_test.rb`
Expected: new tests FAIL (undefined path helper), existing tests PASS.

- [ ] **Step 3: Implement routes and controller**

`config/routes.rb` — extend the existing collection block:

```ruby
          collection do
            get :bulk_print
            get :bulk_new
            post :bulk_create
          end
```

`app/controllers/owner/restaurant_tables_controller.rb` — add after `bulk_print`:

```ruby
    def bulk_new
      @generation = TableBulkGeneration.new(restaurant: @restaurant, floor_label: t("owner.tables.bulk.floor_default"))
    end

    def bulk_create
      @generation = TableBulkGeneration.new(restaurant: @restaurant, **bulk_params.to_h.symbolize_keys)

      if @generation.save
        redirect_to owner_restaurant_tables_path(@restaurant), notice: bulk_notice(@generation), status: :see_other
      else
        render :bulk_new, status: :unprocessable_entity
      end
    end
```

and in the `private` section:

```ruby
    def bulk_params
      params.require(:table_bulk_generation).permit(:floors_count, :tables_per_floor, :floor_label, :name_pattern)
    end

    def bulk_notice(generation)
      if generation.skipped_count.positive?
        t("owner.tables.bulk.created_with_skipped", created: generation.created_count, skipped: generation.skipped_count)
      else
        t("owner.tables.bulk.created", created: generation.created_count)
      end
    end
```

Locales — add to the `bulk:` subtree from Task 1:

en:
```yaml
        created: "%{created} tables created."
        created_with_skipped: "%{created} tables created, %{skipped} skipped (name already in use)."
```

it:
```yaml
        created: "%{created} tavoli creati."
        created_with_skipped: "%{created} tavoli creati, %{skipped} saltati (nome già in uso)."
```

Note: `bulk_new` renders `bulk_new.html.erb`, which doesn't exist until Task 3. For this task's tests to pass, create a minimal placeholder `app/views/owner/restaurant_tables/bulk_new.html.erb` containing just `<h1><%= t("owner.tables.bulk.title") %></h1>` plus the en/it `title:` keys (en: `"Generate Tables"`, it: `"Genera tavoli"`); Task 3 replaces it with the real form.

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/integration/owner/restaurant_tables_controller_test.rb`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/owner/restaurant_tables_controller.rb app/views/owner/restaurant_tables/bulk_new.html.erb config/locales/en.yml config/locales/it.yml test/integration/owner/restaurant_tables_controller_test.rb
git commit -m "feat: bulk_new/bulk_create actions for table generation"
```

---

### Task 3: Generation form UI + entry points + system test

**Files:**
- Modify: `app/views/owner/restaurant_tables/bulk_new.html.erb` (replace placeholder)
- Modify: `app/views/owner/restaurant_tables/index.html.erb` (header + empty-state buttons)
- Modify: `config/locales/en.yml` + `config/locales/it.yml` (form labels)
- Test: `test/system/owner_restaurant_tables_test.rb` (append)

**Interfaces:**
- Consumes: `@generation` (TableBulkGeneration) from Task 2; `TableBulkGeneration::NAME_PATTERNS`, `MAX_FLOORS`, `MAX_TABLES_PER_FLOOR`; existing daisyUI 5 field classes (`field`, `field-label`, `input`, `form-section`, `form-actions`, `btn-wine`).
- Produces: user-facing flow: index → "Generate tables" → form → submit → grouped index with notice.

- [ ] **Step 1: Write the failing system test**

Append to `test/system/owner_restaurant_tables_test.rb`, following the file's existing sign-in and interaction style (read it first):

```ruby
  test "owner bulk-generates tables by floor" do
    visit owner_restaurant_tables_path(@restaurant)
    click_on I18n.t("owner.tables.bulk.generate")

    fill_in I18n.t("owner.tables.bulk.floors_count"), with: 2
    fill_in I18n.t("owner.tables.bulk.tables_per_floor"), with: 3
    fill_in I18n.t("owner.tables.bulk.floor_label"), with: "Piano"
    choose I18n.t("owner.tables.bulk.patterns.t_number")
    click_on I18n.t("owner.tables.bulk.submit")

    assert_text I18n.t("owner.tables.bulk.created", created: 6)
    assert_text "Piano 1"
    assert_text "Piano 2"
    assert_text "T3"
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/system/owner_restaurant_tables_test.rb`
Expected: new test FAILS (no "Generate tables" link). Chromedriver-version errors are environmental — if the whole file errors that way, note it and rely on the integration coverage.

- [ ] **Step 3: Implement the views**

`app/views/owner/restaurant_tables/bulk_new.html.erb`:

```erb
<% content_for(:title) { "#{@restaurant.name} — #{t('owner.tables.bulk.title')}" } %>

<div class="mb-8">
  <h1 class="font-display text-3xl font-light"><%= t("owner.tables.bulk.title") %></h1>
  <p class="text-sm text-base-content/50 mt-2"><%= t("owner.tables.bulk.intro") %></p>
</div>

<%= form_with model: @generation, url: bulk_create_owner_restaurant_tables_path(@restaurant), scope: :table_bulk_generation, class: "space-y-8 max-w-xl" do |f| %>
  <% if @generation.errors.any? %>
    <div role="alert" class="alert alert-error text-sm">
      <%= icon "warning", css: "size-4" %>
      <div>
        <% @generation.errors.full_messages.each do |msg| %>
          <p><%= msg %></p>
        <% end %>
      </div>
    </div>
  <% end %>

  <fieldset class="form-section">
    <div class="grid sm:grid-cols-2 gap-4">
      <div class="field">
        <%= f.label :floors_count, t("owner.tables.bulk.floors_count"), class: "field-label" %>
        <%= f.number_field :floors_count, min: 1, max: TableBulkGeneration::MAX_FLOORS, required: true, class: "input w-full font-body" %>
      </div>
      <div class="field">
        <%= f.label :tables_per_floor, t("owner.tables.bulk.tables_per_floor"), class: "field-label" %>
        <%= f.number_field :tables_per_floor, min: 1, max: TableBulkGeneration::MAX_TABLES_PER_FLOOR, required: true, class: "input w-full font-body" %>
      </div>
    </div>

    <div class="field">
      <%= f.label :floor_label, t("owner.tables.bulk.floor_label"), class: "field-label" %>
      <%= f.text_field :floor_label, class: "input w-full font-body" %>
      <p class="text-xs text-base-content/50 mt-1"><%= t("owner.tables.bulk.floor_label_hint") %></p>
    </div>

    <div class="field">
      <span class="field-label"><%= t("owner.tables.bulk.name_pattern") %></span>
      <div class="space-y-2 mt-1">
        <% TableBulkGeneration::NAME_PATTERNS.each do |pattern| %>
          <label class="flex items-center gap-3 p-3 rounded-lg border border-base-content/10 cursor-pointer hover:border-primary/20 transition-all">
            <%= f.radio_button :name_pattern, pattern, class: "radio radio-primary radio-sm" %>
            <span class="text-sm font-body"><%= t("owner.tables.bulk.patterns.#{pattern}") %></span>
          </label>
        <% end %>
      </div>
    </div>
  </fieldset>

  <div class="form-actions">
    <%= f.submit t("owner.tables.bulk.submit"), class: "btn-wine" %>
    <a href="<%= owner_restaurant_tables_path(@restaurant) %>" class="btn btn-ghost text-xs uppercase tracking-wider"><%= t("shared.cancel") %></a>
  </div>
<% end %>
```

`index.html.erb` — in the header button group, add BEFORE the "Add Table" link:

```erb
      <a href="<%= bulk_new_owner_restaurant_tables_path(@restaurant) %>" class="btn btn-ghost btn-sm">
        <%= icon "magic-wand", css: "size-4" %>
        <%= t("owner.tables.bulk.generate") %>
      </a>
```

and in the empty state, add the same link (as `btn-wine btn-sm`, before the "add first" link, which becomes `btn btn-ghost btn-sm`):

```erb
    <div class="flex items-center justify-center gap-2">
      <a href="<%= bulk_new_owner_restaurant_tables_path(@restaurant) %>" class="btn-wine btn-sm">
        <%= icon "magic-wand", css: "size-4" %>
        <%= t("owner.tables.bulk.generate") %>
      </a>
      <a href="<%= new_owner_restaurant_table_path(@restaurant) %>" class="btn btn-ghost btn-sm">
        <%= icon "plus", css: "size-4" %>
        <%= t("owner.tables.add_first") %>
      </a>
    </div>
```

Icon check: confirm `magic-wand` exists in `app/assets/svg/icons/phosphor/regular/` (per docs/ASSETS.md Phosphor is vendored); if missing, use `sparkle` or `stack-plus`, whichever exists.

Locales — complete the `bulk:` subtree:

en:
```yaml
        generate: "Generate tables"
        title: "Generate Tables"
        intro: "Create all your tables in one go. Floors become rooms; every table gets its own QR code, ready to print."
        floors_count: "Floors"
        tables_per_floor: "Tables per floor"
        floor_label: "Floor name"
        floor_label_hint: "Groups tables by floor, e.g. \"Floor 1\", \"Floor 2\". With a single floor you can leave it blank or use a room name."
        name_pattern: "Table naming"
        patterns:
          table_number: "Table 1, Table 2, …"
          t_number: "T1, T2, …"
          number_only: "1, 2, …"
          floor_table: "1-1, 1-2, … (floor-table)"
        submit: "Generate"
```

it:
```yaml
        generate: "Genera tavoli"
        title: "Genera tavoli"
        intro: "Crea tutti i tavoli in un colpo solo. I piani diventano sale; ogni tavolo ha il suo QR pronto da stampare."
        floors_count: "Piani"
        tables_per_floor: "Tavoli per piano"
        floor_label: "Nome del piano"
        floor_label_hint: "Raggruppa i tavoli per piano, es. \"Piano 1\", \"Piano 2\". Con un solo piano puoi lasciarlo vuoto o usare il nome della sala."
        name_pattern: "Nome dei tavoli"
        patterns:
          table_number: "Tavolo 1, Tavolo 2, …"
          t_number: "T1, T2, …"
          number_only: "1, 2, …"
          floor_table: "1-1, 1-2, … (piano-tavolo)"
        submit: "Genera"
```

(The `patterns.table_number` label is locale-specific on purpose — it previews what the generated names look like in the owner's language.)

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/system/owner_restaurant_tables_test.rb`
Expected: PASS (or environmental chromedriver failure — note which). Then `bin/rails test test/integration/owner/restaurant_tables_controller_test.rb` — PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/owner/restaurant_tables/ config/locales/ test/system/owner_restaurant_tables_test.rb
git commit -m "feat: bulk table generation form and entry points"
```

---

### Task 4: Verification + PR (run by the orchestrator, not a subagent)

- [ ] Run `bin/rubocop`, fix offenses.
- [ ] Run `bin/brakeman -q`, address warnings.
- [ ] Run `bin/bundler-audit update && bin/bundler-audit` (memory: always pre-PR), fix flagged gems.
- [ ] Run full suite once: `bin/rails test` and `bin/rails test:system` (chromedriver failures are environmental).
- [ ] `/security-review` on the diff; `/code-review`; apply CRITICAL/HIGH fixes. (No DB changes → postgres-patterns review not needed.)
- [ ] Rebase on `origin/main`, push `feat/bulk-table-generation`, open PR with summary + test plan. No Claude attribution anywhere.
