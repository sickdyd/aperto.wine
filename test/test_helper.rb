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

# The public menu has one canonical URL — the published list's slug — that
# the restaurant slug and every draft list slug redirect to. Tests asserting
# on menu *content* want to start there rather than following a redirect on
# every request; tests asserting on the redirect itself use the raw helpers.
module PublicMenuPaths
  def published_menu_path(restaurant)
    published = restaurant.published_wine_list
    raise ArgumentError, "#{restaurant.name} has no published wine list" if published.nil?

    Rails.application.routes.url_helpers.wine_list_menu_path(
      restaurant_slug: restaurant.slug, wine_list_slug: published.slug
    )
  end
end

module ActiveSupport
  class TestCase
    # Booting Rails dominates this suite — roughly 60 CPU-seconds of boot for 8s
    # of actual test execution — so workers past a handful buy no measurable
    # wall-clock while each costs a full Rails process, plus a Puma and a
    # headless Chrome in system tests. `:number_of_processors` is 14 on the dev
    # machine, and with several worktree sessions testing at once that
    # oversubscribes it badly enough to make system tests flake on timing.
    # Measured: 14 workers 13.6s, 6 workers 15.5s, for 2.3x the CPU.
    #
    # CI runners have fewer cores than the cap, so they keep using all of them.
    # PARALLEL_WORKERS still overrides this — Rails reads the env var before it
    # looks at the `workers:` argument.
    #
    # `available_processor_count` is what `:number_of_processors` resolves to and
    # respects a container's CPU quota, so keep using it rather than the raw
    # `processor_count`; this only caps that number, it does not replace it.
    max_workers = 6
    available = (Concurrent.available_processor_count || Concurrent.processor_count).floor
    parallelize(workers: [ available, max_workers ].min)
    fixtures :all

    include PhotonStubs
    include PublicMenuPaths

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
