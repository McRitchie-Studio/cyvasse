require "test_helper"

# Browser tests (test/system), run by CI's `test` job with `test:system`.
# Headless Chrome ships on ubuntu-latest; locally Selenium Manager fetches the
# matching driver.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1100 ]
end
