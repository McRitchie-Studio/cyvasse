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
    assert_selector "[data-live-seek-target=computerTag]", text: /computer/i # styled uppercase
    assert_selector "[data-live-seek-target=you]", text: /Guest_\d{4}/
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
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"
    click_on "Play the computer now"

    assert_text(/match found/i, wait: 0.5)
    assert_selector "[data-live-seek-target=computerTag]", text: /computer/i
    assert_selector "[data-controller=cyvasse-match]", wait: 8
    assert_current_path(%r{/matches/\d+})
    assert LiveSeek.last.match.away_user.computer?
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/play-now-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
