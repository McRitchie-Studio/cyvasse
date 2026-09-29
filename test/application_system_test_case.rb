require "test_helper"

# Browser tests (test/system), run by CI's `test` job with `test:system`.
# Headless Chrome ships on ubuntu-latest; locally Selenium Manager fetches the
# matching driver.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SCREEN_SIZE = [ 1400, 1100 ].freeze
  driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE

  # One browser serves every test, so a window a test resized (the admin
  # phone-width tests: Chrome clamps 375px to 500px) would stay that size, and
  # a later test that expects the desktop board would be scrolled, clicked
  # off target, and fail (task cyvasse-system-test-flakes). Put it back.
  teardown do
    window = page.current_window
    window.resize_to(*SCREEN_SIZE) unless window.size == SCREEN_SIZE
  end

  # Waits until every element carrying each Stimulus identifier has its
  # controller connected. stimulus-loading's eagerLoadControllersFrom imports
  # each controller module on its own, so one can connect well after another,
  # and a click on a server-rendered button before its controller connects is
  # lost without a trace (task cyvasse-system-test-flakes). Wait on this, not
  # on the button, before the first click a controller must answer.
  def assert_controllers_connected(*identifiers)
    missing = page.document.synchronize do
      unconnected = page.evaluate_script(<<~JS, identifiers)
        ((ids) => ids.flatMap((id) => {
          const nodes = [...document.querySelectorAll(`[data-controller~="${id}"]`)]
          const live = nodes.length > 0 && window.Stimulus &&
            nodes.every((node) => Stimulus.getControllerForElementAndIdentifier(node, id))
          return live ? [] : [id]
        }))(arguments[0])
      JS
      raise Capybara::ExpectationNotMet, "not connected: #{unconnected.join(", ")}" if unconnected.any?

      unconnected
    end
    assert_empty missing
  end

  # Runs the block with the browser's Math.random seeded (mulberry32) on
  # every page it loads, so /play's army, the computer's lineup, who moves
  # first and the computer's moves are one fixed game rather than a random
  # one that can end before the test's steps run. The browser outlives the
  # test, so the seeding is always removed.
  def with_seeded_random(seed)
    script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      (() => {
        let a = #{Integer(seed)} >>> 0
        Math.random = () => {
          a = (a + 0x6D2B79F5) >>> 0
          let t = Math.imul(a ^ (a >>> 15), a | 1)
          t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
          return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
      })()
    JS
    yield
  ensure
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end

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
