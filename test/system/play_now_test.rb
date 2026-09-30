require "application_system_test_case"

# [e2e] Play Now in a real browser: the landing page's main button, the
# searching countdown, the splash naming both sides, and the match. The
# search and splash are shortened here (config.x); in production they are 20s
# and 5s.
class PlayNowSystemTest < ApplicationSystemTestCase
  setup do
    Rails.configuration.x.live_search_time = 3.seconds
    Rails.configuration.x.live_splash_time = 2.seconds
  end

  teardown do
    Rails.configuration.x.live_search_time = nil
    Rails.configuration.x.live_splash_time = nil
  end

  test "a guest presses Play Now, waits out the search and meets a computer player" do
    visit root_path
    click_on "Play Now"

    assert_text "Finding an opponent"
    assert_selector "[data-live-seek-target=count]", text: /\A[0-3]\z/
    screenshot("searching")
    assert_text(/match found/i, wait: 8)
    assert_selector "[data-live-seek-target=you]", text: /Guest_\d{4}/
    assert_selector "[data-live-seek-target=opponentAvatar] img[data-avatar=bot-portrait][src*='/assets/bots/']"
    assert_quiet_splash
    sleep 0.6 # past the splash's fade-in, for the screenshot
    screenshot("splash")

    assert_selector "[data-controller=cyvasse-match]", wait: 8
    assert_current_path(%r{/matches/\d+})
  end

  test "the splash starts the instant the ring reads 0, before the server answers" do
    Rails.configuration.x.live_search_time = 20.seconds
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"

    # Cut the page off from the server, then end the search on the page's own
    # clock: its end becomes the server time it was rendered with.
    page.execute_script(<<~JS)
      window.fetch = () => new Promise(() => {})
      const el = document.querySelector("[data-controller=live-seek]")
      el.dataset.liveSeekEndsAtValue = el.dataset.liveSeekServerTimeValue
    JS

    assert_text(/match found/i, wait: 0.5)
    assert_selector "[data-live-seek-target=you]", text: /Guest_\d{4}/
    assert_selector "[data-live-seek-target=opponent]", text: "…"
    assert_no_text "Finding an opponent"
    assert_nil LiveSeek.last.match, "the splash did not wait for the server"
  end

  test "play the computer now skips the wait" do
    Rails.configuration.x.live_search_time = 20.seconds
    # Long enough for full_bleed_screenshots' four shots before the match opens.
    Rails.configuration.x.live_splash_time = 8.seconds if ENV["SCREENSHOTS"]
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"
    click_on "Play the computer now"

    assert_text(/match found/i, wait: 0.5)
    assert_selector "[data-live-seek-target=computerTag]", text: "Computer"
    portrait = find("[data-live-seek-target=opponentAvatar] img[data-avatar=bot-portrait]")
    assert_equal LiveSeek.last.match.away_user.player_name, portrait[:alt]
    assert_quiet_splash
    splash_screenshots
    full_bleed_screenshots
    assert_selector "[data-controller=cyvasse-match]", wait: 12
    assert_current_path(%r{/matches/\d+})
    assert LiveSeek.last.match.away_user.computer?
  end

  private

  # The splash wears the versus card's faces (task cyvasse-full-bleed-home):
  # a guest has no photo, so their avatar is their piece from players/avatar,
  # and "You" and "Computer" are quiet small-caps captions, not coloured pills.
  def assert_quiet_splash
    guest = LiveSeek.last.user
    within("[data-live-seek-target=splash]") do
      assert_selector "[data-side=me] [data-avatar=piece][aria-label='#{guest.player_name}'] img[src*='/assets/']"
      assert_selector "[data-side=me] .player-caption", text: "You"
      assert_selector "[data-side=them] .player-caption", text: "Computer"
      assert_no_selector "[data-avatar=pending]"
    end
    %w[me them].each do |side|
      caps, transform, background = page.evaluate_script(<<~JS)
        (s => [s.fontVariantCaps, s.textTransform, s.backgroundColor])(getComputedStyle(document.querySelector("[data-side=#{side}] .player-caption")))
      JS
      assert_equal "all-small-caps", caps, "#{side}: small caps, like the versus card"
      assert_equal "none", transform, "#{side}: not shouted in capitals"
      assert_equal "rgba(0, 0, 0, 0)", background, "#{side}: no pill"
    end
  end

  # SCREENSHOTS=1: the splash in each theme, desktop and 390px, as
  # tmp/screenshots/full-bleed-splash-*.png.
  def full_bleed_screenshots
    return unless ENV["SCREENSHOTS"]

    sleep 0.4
    %w[light dark].each do |theme|
      page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", theme == "dark")
      page.save_screenshot(Rails.root.join("tmp/screenshots/full-bleed-splash-desktop-#{theme}.png"))
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
      begin
        sleep 0.2
        page.save_screenshot(Rails.root.join("tmp/screenshots/full-bleed-splash-390-#{theme}.png"))
      ensure
        page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      end
    end
  end

  # The splash with a computer player's portrait, at desktop and 390px.
  def splash_screenshots
    return unless ENV["SCREENSHOTS"]

    sleep 0.4
    page.save_screenshot(Rails.root.join("tmp/screenshots/bot-portraits-splash-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    begin
      sleep 0.2
      page.save_screenshot(Rails.root.join("tmp/screenshots/bot-portraits-splash-390.png"))
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/play-now-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
