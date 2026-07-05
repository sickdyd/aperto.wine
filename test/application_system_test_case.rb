require "test_helper"
require "minitest/retry"

# Retry only browser tests. This file is loaded solely for system tests (CI runs
# `test` and `test:system` as separate jobs), so unit/integration tests are never
# retried. A genuine regression still fails every attempt; a one-off dropped
# click self-heals. `verbose` prints each retry so flakiness stays visible.
Minitest::Retry.use!(retry_count: 2, verbose: true)

# System tests drive a real headless Chrome via Selenium. Flakiness here comes
# from two places, both addressed below:
#   1. Async Turbo/Stimulus boot + slow first-load (asset build) racing ahead of
#      Capybara — a generous wait gives navigation time to settle. CSS
#      transitions are disabled in the test layout so clicks never land
#      mid-animation (see layouts/application.html.erb).
#   2. Chrome crashing/hanging inside CI containers — hardening flags.
Capybara.default_max_wait_time = ENV["CI"] ? 10 : 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ] do |options|
    # The default /dev/shm is tiny in CI containers; without this Chrome can
    # crash on larger pages, surfacing as random navigation failures.
    options.add_argument("--disable-dev-shm-usage")
    # Suppress first-run prompts that can steal focus from the page under test.
    options.add_argument("--disable-search-engine-choice-screen")
    options.add_argument("--disable-features=Translate")
  end
end
