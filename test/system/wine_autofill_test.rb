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
