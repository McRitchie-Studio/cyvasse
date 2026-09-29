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

      random_setup!
      watch_widest_page
      click_on "Ready"

      # The opening banner hands over to the turn banner; wait until a turn
      # banner has slid in, slid out, and gone.
      assert_selector ".cyvasse-banner.is-showing", text: /Turn 1 ·/, wait: 10
      assert_banner_left
      screenshot("play-#{width}-leaving")
      assert_selector ".cyvasse-banner", visible: :hidden, wait: 10
      assert_no_selector ".cyvasse-banner", wait: 5

      assert_fits width
      widest = page.evaluate_script("window.__widestPage")
      assert_operator widest, :<=, width, "the page never grew wider than the phone while the banners moved"
      screenshot("play-#{width}-after")
    end
  end

  test "the online match board has no sideways scroll at 390px while its turn banner comes and goes" do
    arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    match = Match.start_live!(arya, computer: true, rng: Random.new(4))
    visit link_path(token: Studio::Link.create_magic_link(email: arya.email).token)
    assert_text "Signed in as Arya"

    phone!(390)
    visit match_path(match)
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_fits 390

    random_setup!
    watch_widest_page
    click_on "Ready"

    assert_selector ".cyvasse-banner.is-showing", text: /Turn \d+ ·/, wait: 10
    assert_banner_left
    screenshot("match-390-leaving")
    assert_no_selector ".cyvasse-banner", wait: 5

    assert_fits 390
    widest = page.evaluate_script("window.__widestPage")
    assert_operator widest, :<=, 390, "the page never grew wider than the phone while the banner moved"
  end

  test "the board's sideways clip leaves room for the start-over hint's focus ring" do
    visit play_path
    assert_selector "svg.cyvasse-board g.hex", count: 91
    page.execute_script("document.querySelector('.cyvasse-hint').hidden = false")
    gap = page.evaluate_script(<<~JS)
      document.querySelector('.cyvasse-hint').getBoundingClientRect().left -
        document.querySelector('.cyvasse-board-wrap').getBoundingClientRect().left
    JS
    assert_operator gap, :>=, 3, "a focus ring drawn outside the hint fits inside the clipped wrap"
  end

  private

  # Place the army. On a phone, Random Setup sits below the fold, so the click
  # first scrolls it into view, and that scroll collapses the engine's sticky,
  # in-flow navbar (navCollapse: 32px here, 4px a frame). The page slides up
  # under a click already aimed, and on a loaded CI runner it lands below the
  # button: a silent no-op, 19 units still in the dock. CI runs 36556041722
  # and 36555774130 both show it, one warm and one cold. The load wait
  # below only rules out a page still painting; it cannot see a collapse that
  # the click's own scroll starts. The confirm-and-retry is the fix: by the
  # second click the page is scrolled and the navbar settled. A second click
  # is harmless: Random Setup only ever places or reshuffles your own army.
  def random_setup!
    assert page.evaluate_async_script(<<~JS), "the page finished loading"
      const done = arguments[arguments.length - 1]
      const loaded = document.readyState === "complete" ? Promise.resolve() :
        new Promise((resolve) => window.addEventListener("load", resolve, { once: true }))
      loaded.then(() => document.fonts.ready).then(() => requestAnimationFrame(() => done(true)))
    JS
    2.times do
      click_on "Random Setup"
      break if has_no_selector?(".cyvasse-dock .dock-unit", wait: 3)
    end
    assert_no_selector ".cyvasse-dock .dock-unit"
  end

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

  # is-leaving lives 600ms, or less when the next banner cuts in, which a
  # Capybara poll on a loaded runner can step right over. The watcher latches
  # it on <html> the moment a banner starts to leave; wait on the latch.
  def assert_banner_left
    assert_selector "html[data-banner-left]", visible: :all, wait: 10
  end

  # Record the page's widest scrollWidth every frame from here on, so a banner
  # that widens the page only while it slides out is caught too.
  def watch_widest_page
    page.execute_script(<<~JS)
      delete document.documentElement.dataset.bannerLeft
      new MutationObserver(() => {
        if (document.querySelector(".cyvasse-banner.is-leaving")) document.documentElement.dataset.bannerLeft = ""
      }).observe(document.body, { subtree: true, attributes: true, attributeFilter: ["class"] })
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
