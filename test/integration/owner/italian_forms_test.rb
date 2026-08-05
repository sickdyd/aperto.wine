require "test_helper"

module Owner
  # Production runs in Italian (config/application.rb sets default_locale :it),
  # but the rest of the suite runs under :en, so a half-translated owner form
  # would ship unnoticed. These tests drive each owner form under an explicit
  # `locale: "it"` prefix and assert the model layer — the submit button
  # (`f.submit` with no label => "Crea %{model}") and the validation errors —
  # renders in Italian with no English fragment left behind. This is what would
  # have caught "Crea Wine list" and "Name can't be blank".
  class ItalianFormsTest < ActionDispatch::IntegrationTest
    setup do
      @owner = users(:owner)
      @restaurant = restaurants(:osteria)
      sign_in_as @owner
    end

    # --- Restaurant ---

    test "new restaurant form submit button is Italian" do
      get new_owner_restaurant_path(locale: "it")
      assert_response :success
      assert_includes response.body, "Crea Ristorante"
      assert_no_english_model_name
    end

    test "invalid restaurant renders Italian validation errors" do
      post owner_restaurants_path(locale: "it"), params: {
        restaurant: { name: "", address: "", proximity_radius_meters: 0 }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "Nome non può essere lasciato in bianco"
      assert_includes response.body, "Indirizzo non può essere lasciato in bianco"
      assert_no_english_errors
    end

    # --- Wine ---

    test "new wine form submit button is Italian" do
      get new_owner_restaurant_wine_path(restaurant_id: @restaurant, locale: "it")
      assert_response :success
      assert_includes response.body, "Crea Vino"
      assert_no_english_model_name
    end

    test "invalid wine renders Italian validation errors" do
      post owner_restaurant_wines_path(restaurant_id: @restaurant, locale: "it"), params: {
        wine: { name: "", bottle_size_ml: 750, available_glasses: 0 }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "Nome non può essere lasciato in bianco"
      assert_no_english_errors
    end

    # --- Wine list ---

    test "new wine list form submit button is Italian" do
      get new_owner_restaurant_wine_list_path(restaurant_id: @restaurant, locale: "it")
      assert_response :success
      assert_includes response.body, "Crea Lista"
      assert_no_english_model_name
    end

    test "invalid wine list renders Italian validation errors" do
      post owner_restaurant_wine_lists_path(restaurant_id: @restaurant, locale: "it"), params: {
        wine_list: { name: "" }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "Nome non può essere lasciato in bianco"
      assert_no_english_errors
    end

    # --- Restaurant table ---

    test "new table form submit button is Italian" do
      get new_owner_restaurant_table_path(restaurant_id: @restaurant, locale: "it")
      assert_response :success
      assert_includes response.body, "Crea Tavolo"
      assert_no_english_model_name
    end

    test "invalid table renders Italian validation errors" do
      post owner_restaurant_tables_path(restaurant_id: @restaurant, locale: "it"), params: {
        restaurant_table: { name: "" }
      }
      assert_response :unprocessable_entity
      assert_includes response.body, "Nome non può essere lasciato in bianco"
      assert_no_english_errors
    end

    private

    # The four models whose forms use a bare `f.submit`; none of their English
    # names should leak into an Italian page.
    def assert_no_english_model_name
      [ "Crea Restaurant", "Crea Wine", "Crea Wine list", "Crea Restaurant table" ].each do |fragment|
        assert_not_includes response.body, fragment, "English model name leaked: #{fragment}"
      end
    end

    def assert_no_english_errors
      [ "can't be blank", "must exist", "is not a number", "must be greater than" ].each do |fragment|
        assert_not_includes response.body, fragment, "English validation fragment leaked: #{fragment}"
      end
    end
  end
end
