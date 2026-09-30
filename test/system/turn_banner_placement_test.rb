require "application_system_test_case"

# [e2e] The turn banner ("Turn 3 · Your move") never covers the board, on
# /play and on a live match, at desktop width and on a 390px phone. It once
# sat over board rows 4-5 on every turn change, hiding the computer's
# selected unit and its move (UX audit #2). A watcher checks every animation
# frame from Ready on, so a banner that crosses the board only while it
# slides in or out is caught too. SHOTS_DIR=<dir> saves a screenshot of each
# case with the banner up.
class TurnBannerPlacementTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  [ nil, 390 ].each do |width|
    label = width ? "#{width}px" : "desktop"

    test "/play: the turn banner never overlaps the board (#{label})" do
      phone!(width) if width
      visit play_path
      assert_selector "svg.cyvasse-board g.hex", count: 91

      smart_setup!
      watch_overlap
      click_on "Ready"

      assert_selector ".cyvasse-banner.is-showing", text: /Turn 1 ·/, wait: 10
      shot("play-#{label}")
      assert_selector ".cyvasse-banner", visible: :hidden, wait: 10
      assert_never_overlapped
    end

    test "a live match: the turn banner never overlaps the board (#{label})" do
      arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
      match = Match.start_live!(arya, computer: true, rng: Random.new(4))
      visit link_path(token: Studio::Link.create_magic_link(email: arya.email).token)
      assert_text "Signed in as arya"

      phone!(width) if width
      visit match_path(match)
      assert_selector ".cyvasse-dock .dock-unit", count: 19

      smart_setup!
      watch_overlap
      click_on "Ready"

      assert_selector ".cyvasse-banner.is-showing", text: /Turn \d+ ·/, wait: 10
      shot("match-#{label}")
      assert_selector ".cyvasse-banner", visible: :hidden, wait: 10
      assert_never_overlapped
    end
  end

  private

  def phone!(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 844, deviceScaleFactor: 1, mobile: true)
  end

  # Every frame: the area the showing banner shares with the board's box, the
  # largest seen, and how many frames a banner was showing at all (so a
  # watcher that never saw a banner cannot pass).
  def watch_overlap
    page.execute_script(<<~JS)
      window.__bannerOverlap = 0
      window.__bannerFrames = 0
      const tick = () => {
        const banner = document.querySelector(".cyvasse-banner")
        const board = document.querySelector("svg.cyvasse-board")
        if (banner && board && !banner.hidden && getComputedStyle(banner).opacity > 0) {
          const a = banner.getBoundingClientRect()
          const b = board.getBoundingClientRect()
          const w = Math.min(a.right, b.right) - Math.max(a.left, b.left)
          const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top)
          window.__bannerFrames += 1
          if (w > 0 && h > 0) window.__bannerOverlap = Math.max(window.__bannerOverlap, w * h)
        }
        requestAnimationFrame(tick)
      }
      tick()
    JS
  end

  def assert_never_overlapped
    frames = page.evaluate_script("window.__bannerFrames")
    assert_operator frames, :>, 0, "the watcher saw a banner"
    assert_equal 0, page.evaluate_script("window.__bannerOverlap"), "the banner never covered any of the board"
  end

  def shot(name)
    return unless ENV["SHOTS_DIR"]
    page.save_screenshot(File.join(ENV["SHOTS_DIR"], "match-fixes-after-#{name}.png"))
  end
end
