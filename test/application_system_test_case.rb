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

  # Place the army. On a phone, Smart Setup sits below the fold, so the click
  # first scrolls it into view, and that scroll collapses the engine's sticky,
  # in-flow navbar (navCollapse: 32px here, 4px a frame). The page slides up
  # under a click already aimed, and on a loaded CI runner it lands below the
  # button: a silent no-op, 19 units still in the dock. CI runs 36556041722
  # and 36555774130 both show it, one warm and one cold. The load wait
  # below only rules out a page still painting; it cannot see a collapse that
  # the click's own scroll starts. The confirm-and-retry is the fix: by the
  # second click the page is scrolled and the navbar settled. A second click
  # is harmless: Smart Setup only ever places or replaces your own army.
  def smart_setup!
    assert page.evaluate_async_script(<<~JS), "the page finished loading"
      const done = arguments[arguments.length - 1]
      const loaded = document.readyState === "complete" ? Promise.resolve() :
        new Promise((resolve) => window.addEventListener("load", resolve, { once: true }))
      loaded.then(() => document.fonts.ready).then(() => requestAnimationFrame(() => done(true)))
    JS
    2.times do
      find("button.cyvasse-smart").click
      break if has_no_selector?(".cyvasse-dock .dock-unit", wait: 3)
    end
    assert_no_selector ".cyvasse-dock .dock-unit"
  end
end
