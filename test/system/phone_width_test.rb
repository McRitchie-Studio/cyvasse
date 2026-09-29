require "application_system_test_case"

# [e2e] The game boards fit a true phone, before, during and after the
# rotator banner. The banner slides out to the right (translate(50%, -50%)),
# which once pushed a 390px page out to about 545px: on a phone the page then
# scrolled sideways or zoomed out for the rest of the game. A desktop Chrome
# window will not shrink that far, so Chrome's device emulation sets the
# width. SCREENSHOTS=1 saves each step to tmp/screenshots.
class PhoneWidthTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  [ 390, 375 ].each do |width|
    test "/play has no sideways scroll at #{width}px while a turn banner comes and goes" do
      phone!(width)
      visit play_path
      assert_selector "svg.cyvasse-board g.hex", count: 91
      assert_fits width

      click_on "Random Setup"
      assert_no_selector ".cyvasse-dock .dock-unit"
      watch_widest_page
      click_on "Ready"

      # The opening banner hands over to the turn banner; wait until a turn
      # banner has slid in, slid out, and gone.
      assert_selector ".cyvasse-banner.is-showing", text: /Turn 1 ·/, wait: 10
      assert_selector ".cyvasse-banner.is-leaving", wait: 10
      screenshot("play-#{width}-leaving")
      assert_selector ".cyvasse-banner", visible: :hidden, wait: 10
      assert_no_selector ".cyvasse-banner", wait: 5

      assert_fits width
      widest = page.evaluate_script("window.__widestPage")
      assert_operator widest, :<=, width, "the page never grew wider than the phone while the banners moved"
      screenshot("play-#{width}-after")
    end
  end

  private

  # A true phone viewport.
  def phone!(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 844, deviceScaleFactor: 1, mobile: true)
  end

  def assert_fits(width)
    scroll, client = page_widths
    assert_equal width, client, "the viewport is a #{width}px phone's"
    assert_operator scroll, :<=, client, "no sideways scroll at #{width}px"
  end

  # Record the page's widest scrollWidth every frame from here on, so a banner
  # that widens the page only while it slides out is caught too.
  def watch_widest_page
    page.execute_script(<<~JS)
      window.__widestPage = 0
      const tick = () => {
        window.__widestPage = Math.max(window.__widestPage, document.documentElement.scrollWidth)
        requestAnimationFrame(tick)
      }
      tick()
    JS
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/phone-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
