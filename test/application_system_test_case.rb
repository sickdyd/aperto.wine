require "test_helper"

# Give Capybara more headroom on first-load (asset build) and Turbo redirects
# so a slow render doesn't intermittently fail an assertion.
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]
end
