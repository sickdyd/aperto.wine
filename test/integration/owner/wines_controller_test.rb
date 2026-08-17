require "test_helper"

module Owner
  class WinesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
      @wine = wines(:barolo)
    end

    # --- Authorization ---

    test "GET /owner/restaurants/:id/wines requires authentication" do
      get owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_redirected_to sign_in_path
    end

    test "GET /owner/restaurants/:id/wines as customer is unauthorized" do
      sign_in_as users(:customer)
      get owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_redirected_to root_path
    end

    # --- INDEX ---

    test "GET /owner/restaurants/:id/wines as owner renders index" do
      sign_in_as @owner
      get owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_response :success
    end

    # --- NEW ---

    test "GET /owner/restaurants/:id/wines/new as owner renders new form" do
      sign_in_as @owner
      get new_owner_restaurant_wine_path(restaurant_id: @restaurant)
      assert_response :success
    end

    # --- CREATE ---

    test "POST /owner/restaurants/:id/wines with valid params creates wine" do
      sign_in_as @owner
      assert_difference "Wine.count", 1 do
        post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
          wine: {
            name: "Amarone della Valpolicella",
            producer: "Allegrini",
            grape_variety: "Corvina",
            vintage_year: 2019,
            color: "red",
            region: "Veneto",
            bottle_size_ml: 750,
            price_100ml_cents: 2000,
            price_125ml_cents: 2500,
            available_glasses: 6,
            position: 2,
            active: true
          }
        }
      end
      created = Wine.find_by(name: "Amarone della Valpolicella")
      assert_not_nil created
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
    end

    test "POST /owner/restaurants/:id/wines with invalid params re-renders new form" do
      sign_in_as @owner
      assert_no_difference "Wine.count" do
        post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
          wine: {
            name: "",
            bottle_size_ml: 750,
            available_glasses: 0
          }
        }
      end
      assert_response :unprocessable_entity
    end

    test "POST /owner/restaurants/:id/wines with invalid params wires each error to its field" do
      sign_in_as @owner
      post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
        wine: { name: "", bottle_size_ml: "", available_glasses: -1, price_bottle_cents: 1500 }
      }
      assert_response :unprocessable_entity

      # The summary at the top stays; the inline errors complement it.
      assert_select "div[role=alert] p", minimum: 3

      {
        "wine_name" => "wine_name_error_0",
        "wine_bottle_size_ml" => "wine_bottle_size_ml_error_0",
        "wine_available_glasses" => "wine_available_glasses_hint wine_available_glasses_error_0"
      }.each do |field_id, described_by|
        assert_select "##{field_id}[aria-invalid=?]", "true"
        assert_select "##{field_id}[aria-describedby=?]", described_by
      end

      described_ids = css_select("[aria-describedby]").flat_map { |node| node["aria-describedby"].split }
      css_select("p.field-error").each do |error|
        assert_includes described_ids, error["id"],
          "inline error #{error['id']} is not referenced by any aria-describedby"
      end

      # Fields that validated fine must not claim to be invalid.
      assert_select "#wine_price_bottle_cents[aria-invalid]", false
      assert_select "#wine_region[aria-invalid]", false
    end

    # --- Character & tasting fields (Task 3) ---

    test "POST with character fields creates a wine with them all set" do
      sign_in_as @owner
      post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
        wine: {
          name: "Etna Rosso",
          color: "red",
          bottle_size_ml: 750,
          available_glasses: 4,
          price_125ml_cents: 1200,
          abv: 13.5,
          style: "Volcanic",
          short_description: "A smoky red from the mountain's north slope.",
          body: 3, tannins: 4, acidity: 4, sweetness: 1,
          organic: "1", natural_wine: "0", vegan: "1", biodynamic: "0",
          aromas_list: "smoke, red cherry,  , plum",
          food_pairings_list: "grilled lamb, aged pecorino"
        }
      }
      created = Wine.find_by(name: "Etna Rosso")
      assert_not_nil created
      assert_in_delta 13.5, created.abv, 0.01
      assert_equal "Volcanic", created.style
      assert_equal "A smoky red from the mountain's north slope.", created.short_description
      assert_equal 3, created.body
      assert_equal 4, created.tannins
      assert_equal 4, created.acidity
      assert_equal 1, created.sweetness
      assert created.organic?
      assert_not created.natural_wine?
      assert created.vegan?
      assert_not created.biodynamic?
      assert_equal [ "smoke", "red cherry", "plum" ], created.aromas
      assert_equal [ "grilled lamb", "aged pecorino" ], created.food_pairings
    end

    test "POST with an aromas_list left blank submits with no error and an empty aromas array" do
      sign_in_as @owner
      assert_difference "Wine.count", 1 do
        post owner_restaurant_wines_path(restaurant_id: @restaurant), params: {
          wine: {
            name: "Blank Aromas Wine",
            color: "white",
            bottle_size_ml: 750,
            available_glasses: 2,
            price_100ml_cents: 900,
            aromas_list: "",
            food_pairings_list: ""
          }
        }
      end
      created = Wine.find_by(name: "Blank Aromas Wine")
      assert_equal [], created.aromas
      assert_equal [], created.food_pairings
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
    end

    test "PATCH updates character fields on an existing wine" do
      sign_in_as @owner
      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: {
          abv: 14.2,
          style: "Traditional",
          short_description: "Updated tasting note.",
          body: 5, tannins: 5, acidity: 3, sweetness: 0,
          organic: "1", natural_wine: "1", vegan: "0", biodynamic: "1",
          aromas_list: "tar, rose",
          food_pairings_list: "braised short rib"
        }
      }
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
      @wine.reload
      assert_in_delta 14.2, @wine.abv, 0.01
      assert_equal "Traditional", @wine.style
      assert_equal "Updated tasting note.", @wine.short_description
      assert_equal [ 5, 5, 3, 0 ], [ @wine.body, @wine.tannins, @wine.acidity, @wine.sweetness ]
      assert @wine.organic?
      assert @wine.natural_wine?
      assert_not @wine.vegan?
      assert @wine.biodynamic?
      assert_equal [ "tar", "rose" ], @wine.aromas
      assert_equal [ "braised short rib" ], @wine.food_pairings
    end

    test "the raw aromas/food_pairings array attributes are not mass-assignable" do
      sign_in_as @owner
      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: { name: @wine.name, aromas: [ "smuggled" ], food_pairings: [ "smuggled" ] }
      }
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
      @wine.reload
      assert_equal [], @wine.aromas
      assert_equal [], @wine.food_pairings
    end

    # --- EDIT ---

    test "GET /owner/restaurants/:id/wines/:id/edit as owner renders edit form" do
      sign_in_as @owner
      get edit_owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine)
      assert_response :success
    end

    # --- UPDATE ---

    test "PATCH /owner/restaurants/:id/wines/:id with valid params updates wine" do
      sign_in_as @owner
      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: { name: "Barolo Riserva DOCG" }
      }
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_equal "Barolo Riserva DOCG", @wine.reload.name
    end

    test "PATCH /owner/restaurants/:id/wines/:id with invalid params re-renders edit form" do
      sign_in_as @owner
      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: { name: "", bottle_size_ml: -1 }
      }
      assert_response :unprocessable_entity
    end

    # --- optimistic locking on available_glasses ---
    #
    # available_glasses is a live reservation counter now: diners spend it
    # while the owner's form sits open, but the form edits it as an absolute
    # number seeded when the page was rendered. Without a version check, an
    # owner who opened the form at 10, watched four glasses get reserved, and
    # then saved an unrelated typo fix would write 10 straight back and
    # resurrect the four reserved glasses. Minutes-long window, not a race.

    test "the edit form carries the version it was rendered from" do
      sign_in_as @owner
      get edit_owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine)

      assert_select "input[type=hidden][name='wine[lock_version]'][value=?]", @wine.lock_version.to_s
    end

    test "a save carrying a stale version neither wins nor is silently dropped" do
      sign_in_as @owner
      stale_version = @wine.lock_version
      # What a diner's placement does to the row while the form sits open.
      @wine.decrement!(:available_glasses, 4)
      glasses_now = @wine.reload.available_glasses

      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: { name: "Barolo Riserva DOCG", available_glasses: glasses_now + 4, lock_version: stale_version }
      }

      assert_response :conflict
      # The reserved glasses are not resurrected, and the edit that rode along
      # with them is not applied either.
      assert_equal glasses_now, @wine.reload.available_glasses
      assert_equal "Barolo Riserva", @wine.name
      # The owner is told what happened and shown the figure they were wrong
      # about, rather than left believing the save went through.
      assert_match ERB::Util.html_escape(I18n.t("owner.wines.stale_update", glasses: glasses_now)), response.body
      assert_select "input[name='wine[available_glasses]'][value=?]", glasses_now.to_s
    end

    test "a save carrying the current version still goes through" do
      sign_in_as @owner
      @wine.decrement!(:available_glasses, 4)
      current = @wine.reload

      patch owner_restaurant_wine_path(restaurant_id: @restaurant, id: @wine), params: {
        wine: { name: "Barolo Riserva DOCG", lock_version: current.lock_version }
      }

      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
      assert_equal "Barolo Riserva DOCG", @wine.reload.name
    end

    # --- DESTROY ---

    test "DELETE /owner/restaurants/:id/wines/:id destroys wine and redirects" do
      sign_in_as @owner
      # Use sold_out_wine which has no order_items referencing it
      wine_to_delete = wines(:sold_out_wine)
      assert_difference "Wine.count", -1 do
        delete owner_restaurant_wine_path(restaurant_id: @restaurant, id: wine_to_delete)
      end
      assert_redirected_to owner_restaurant_wines_path(restaurant_id: @restaurant)
    end

    # --- Cross-owner protection ---

    test "GET /owner/restaurants/:id/wines for another owner's restaurant returns 404" do
      other_owner = User.create!(
        name: "Other Owner",
        email: "other2@example.com",
        password: "password123",
        role: "owner",
        confirmed_at: Time.current
      )
      other_restaurant = other_owner.restaurants.create!(
        name: "Other Place",
        address: "Via Test 2",
        proximity_radius_meters: 100
      )

      sign_in_as @owner
      get owner_restaurant_wines_path(restaurant_id: other_restaurant)
      assert_response :not_found
    end
  end
end
