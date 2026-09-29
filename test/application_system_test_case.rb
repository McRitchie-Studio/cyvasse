require "test_helper"

# Browser tests (test/system), run by CI's `test` job with `test:system`.
# Headless Chrome ships on ubuntu-latest; locally Selenium Manager fetches the
# matching driver.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1100 ]

  # [scrollWidth, clientWidth] of the page once any view transition has
  # finished. Studio.smooth_load wraps each Turbo visit in one, and mid-flight
  # its overlay spans the whole window, scrollbar gutter included, so a width
  # read then reports sideways scroll that the page does not have.
  def page_widths
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const settle = () => Promise.all(document.getAnimations()
        .filter((a) => (a.effect?.pseudoElement || "").startsWith("::view-transition"))
        .map((a) => a.finished.catch(() => {})))
      settle().then(() => requestAnimationFrame(() =>
        done([document.documentElement.scrollWidth, document.documentElement.clientWidth])))
    JS
  end
end
