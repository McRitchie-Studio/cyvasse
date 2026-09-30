require "application_system_test_case"

# [e2e] WCAG AA contrast of Cyvasse's green and gold, measured in the browser
# from getComputedStyle, in the light theme and the dark (task
# cyvasse-contrast-and-names; production UX audit finding 9): the gold "Log in"
# button and Play Now, the green buttons on /play, and the gold text of the
# navbar's app name and current-page link, and the gold text on a card.
# Normal-size text owes 4.5:1, and every one of these is held to it, the 30px
# app name included. Also, at 390px the signed-in navbar shows one theme
# toggle and no truncated name (finding 10). test/lib/light_mode_contrast_test.rb
# holds the same shades as numbers.
# SCREENSHOTS=1 saves each view to tmp/screenshots/contrast-*.png.
class ContrastSystemTest < ApplicationSystemTestCase
  AA = 4.5

  # The contrast of an element's text on the nearest opaque background under
  # it, from the computed colours. A canvas turns any CSS colour into sRGB.
  RATIO_JS = <<~JS.freeze
    ((el) => {
      const cv = document.createElement("canvas"); cv.width = cv.height = 1
      const cx = cv.getContext("2d", { willReadFrequently: true })
      const rgba = (css) => { cx.clearRect(0, 0, 1, 1); cx.fillStyle = "rgba(0,0,0,0)"; cx.fillStyle = css; cx.fillRect(0, 0, 1, 1); return cx.getImageData(0, 0, 1, 1).data }
      let ground = null
      for (let node = el; node && !ground; node = node.parentElement) {
        const bg = rgba(getComputedStyle(node).backgroundColor)
        if (bg[3] === 255) ground = bg
      }
      ground = ground || [255, 255, 255, 255]
      const lum = (c) => { const [r, g, b] = [0, 1, 2].map((i) => { const v = c[i] / 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4 }); return 0.2126 * r + 0.7152 * g + 0.0722 * b }
      const [a, b] = [lum(rgba(getComputedStyle(el).color)), lum(ground)]
      return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
    })(arguments[0])
  JS

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.execute_script("try { localStorage.removeItem('theme') } catch (e) {}")
  end

  %w[light dark].each do |theme|
    test "#{theme}: the gold Log in button and the gold navbar name clear AA" do
      visit_in_theme(root_path, theme)

      assert_aa find("header[data-pin=nav] a.btn-primary", text: "Log in"), "Log in (btn-primary)"
      assert_aa find("header[data-pin=nav] .nav-title .text-primary"), "the navbar's gold app name"
      assert_aa find("section.home-hero form button.btn-primary", text: "Play Now"), "Play Now (btn-primary)"
      assert_aa find("[data-leaderboard-card] .leaderboard-inline-cta strong", text: "Play Now"), "the gold Play Now on the leaderboard card"
      screenshot("home-#{theme}")
    end

    test "#{theme}: the green buttons on /play and the gold current-page link clear AA" do
      guest = User.create_guest!(rng: Random.new(11))
      guest.update!(email: "contrast-#{theme}@example.com")
      visit link_path(token: Studio::Link.create_magic_link(email: guest.email).token)
      assert_text "Signed in as #{guest.player_name}"

      visit_in_theme(play_path, theme)
      buttons = all("button.btn-secondary", minimum: 1)
      buttons.each { |button| assert_aa button, "green #{button.text.inspect} (btn-secondary)" }

      visit_in_theme(leaderboard_path, theme)
      assert_aa find("nav[aria-label=Main] a[aria-current=page]", match: :first), "the gold current-page link"
      screenshot("leaderboard-#{theme}")
    end
  end

  # The setup clock in the phone dock turns red in its last seconds. On the
  # dark dock sheet (a bg-surface card) #dc2626 was 2.31:1; the dark theme
  # now takes the engine's danger ink. Light mode keeps #dc2626.
  %w[light dark].each do |theme|
    test "#{theme}: the urgent setup clock in the phone dock clears AA" do
      arya = User.create!(email: "arya-#{theme}@example.com", name: "Arya", username: "arya#{theme}")
      match = Match.start_live!(arya, computer: true, rng: Random.new(4))
      visit link_path(token: Studio::Link.create_magic_link(email: arya.email).token)
      assert_text "Signed in as #{arya.player_name}"

      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
      visit_in_theme(match_path(match), theme)
      clock = find(".cyvasse-army .cyvasse-army-clock", text: /\A\d+s\z/)
      # The live clock re-toggles is-warning on every tick, so a one-off add
      # races it; hold the class on for the rest of the test.
      page.execute_script(<<~JS, clock)
        const el = arguments[0]
        const hold = () => { if (!el.classList.contains("is-warning")) el.classList.add("is-warning") }
        hold()
        new MutationObserver(hold).observe(el, { attributes: true, attributeFilter: ["class"] })
      JS

      assert_aa clock, "the urgent setup clock"
      color = page.evaluate_script("getComputedStyle(arguments[0]).color", clock)
      assert_equal "rgb(220, 38, 38)", color, "light mode keeps #dc2626" if theme == "light"
      screenshot("dock-clock-#{theme}")
    end
  end

  test "390px: the signed-in navbar shows one theme toggle and the avatar, not a truncated name" do
    guest = User.create_guest!(rng: Random.new(13))
    guest.update!(email: "contrast-phone@example.com")
    visit link_path(token: Studio::Link.create_magic_link(email: guest.email).token)
    assert_text "Signed in as #{guest.player_name}"

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit root_path
    assert_selector "header[data-pin=nav] button[title='Toggle theme']", visible: true, count: 1
    assert_selector "header[data-pin=nav] a[data-nav-account]", visible: true, count: 1
    # The name is screen-reader text there: in the page, but a 1px clipped box.
    width = page.evaluate_script("document.querySelector('header[data-pin=nav] [data-nav-name]').parentElement.getBoundingClientRect().width")
    assert_operator width, :<=, 1, "the name takes no room on a phone"
    screenshot("navbar-390")
  end

  private

  def visit_in_theme(path, theme)
    visit path
    page.execute_script("localStorage.setItem('theme', arguments[0])", theme)
    visit path
    assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
  end

  def assert_aa(element, label)
    ratio = page.evaluate_script(RATIO_JS, element)
    assert_operator ratio, :>=, AA, "#{label}: #{ratio.round(2)}:1"
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/contrast-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
