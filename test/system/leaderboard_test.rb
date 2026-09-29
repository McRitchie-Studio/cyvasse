require "application_system_test_case"

# [e2e] The leaderboards and a guest's sign-in after a live game, in a real
# browser: the landing page's live leaderboard card (and its empty state) at
# desktop and phone width, the full board's tabs, the game-over modal's call
# on a guest's finished live match, and signing in through the email link to
# put the win on the board. SCREENSHOTS=1 saves each step to tmp/screenshots.
class LeaderboardSystemTest < ApplicationSystemTestCase
  include LiveResults

  setup do
    @qavo = computer
  end

  teardown do
    Rails.configuration.x.live_search_time = nil
    Rails.configuration.x.live_splash_time = nil
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  # A true 375px viewport: a desktop Chrome window will not shrink that far.
  def phone!
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: 375, height: 812, deviceScaleFactor: 1, mobile: true)
  end

  def assert_no_sideways_scroll
    scroll, client = page_widths
    assert_equal 375, client, "the viewport is a phone's"
    assert_operator scroll, :<=, client, "no sideways scroll at phone width"
  end

  test "the landing page's card invites the first player when the board is empty" do
    visit root_path
    within("[data-leaderboard-card]") do
      assert_text "LIVE LEADERBOARD"
      assert_button "Be the first on the board — Play Now"
    end
    screenshot("landing-empty")
  end

  # Alex's report (2026-09-29): games finished as a guest never reached the
  # card. A real Play Now game against the computer, lost by resigning.
  test "finishing a game against the computer puts the guest on the landing board" do
    Rails.configuration.x.live_search_time = 20.seconds
    Rails.configuration.x.live_splash_time = 0.5.seconds
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"
    click_on "Play the computer now"
    assert_selector "[data-controller=cyvasse-match]", wait: 8
    guest = LiveSeek.last.user
    match = Match.involving(guest).last
    match.set_up!(guest, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    # Resigned on the server: a click can beat Turbo's confirm on a slow runner.
    match.reload.resign!(guest)

    visit root_path
    within("[data-leaderboard-card]") do
      assert_no_selector "[data-leaderboard-empty]"
      row = find("[data-leaderboard-row='#{guest.username}'].is-you")
      assert_equal [ "1", "1 pt", "0 W", "1 G" ], %w[rank points wins games].map { row.find("[data-stat=#{_1}]").text.squish }
    end
    screenshot("guest-finished-on-card")

    phone!
    visit root_path
    assert_selector "[data-leaderboard-card] [data-leaderboard-row='#{guest.username}']"
    assert_no_sideways_scroll
    find("[data-leaderboard-card]").scroll_to(:center)
    screenshot("guest-finished-on-card-phone")
  end

  test "the landing card lists the leaders and fits a 375px phone" do
    long = player("a_very_long_username")
    arya = player("arya")
    3.times { live_result(long, @qavo, winner: long) }
    live_result(arya, @qavo, winner: arya)

    visit root_path
    assert_equal %w[a_very_long_username arya], all("[data-leaderboard-card] [data-leaderboard-row]").map { _1["data-leaderboard-row"] }
    screenshot("landing-desktop")

    phone!
    visit root_path
    assert_selector "[data-leaderboard-card] [data-leaderboard-row]", count: 2
    assert_no_sideways_scroll
    find("[data-leaderboard-card]").scroll_to(:center)
    screenshot("landing-phone")

    click_on "See all"
    assert_selector "h1", text: "Leaderboard"
    assert_selector "[data-board=live] [data-leaderboard-row=a_very_long_username]", text: /9\s*pts\s*3\s*W\s*3\s*G/
    assert_no_sideways_scroll
    screenshot("leaderboard-phone")
  end

  test "a guest who wins is asked to sign in, and the win lands on the board" do
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"
    guest = LiveSeek.last.user
    match = live_result(guest, @qavo, winner: guest)

    visit match_path(match)
    within("[data-test=game-over-modal]") do
      assert_selector "h3", text: "You captured the king. You win."
      assert_text "this win goes on the live leaderboard under your name"
    end
    screenshot("guest-win-cta")
    phone!
    assert_no_sideways_scroll
    screenshot("guest-win-cta-phone")
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")

    click_on "Sign in to keep your record"
    fill_in "Email", with: "arya@example.com"
    click_on "Email me a sign-in link"
    assert_text "Check your inbox"

    visit link_path(token: Studio::Link.last.token)
    # A new account finishes itself first (the onboarding), username first.
    assert_selector "[data-onboarding-step=username] h1", text: "Pick a username"
    fill_in "Username", with: "arya"
    click_on "Save username"
    click_on "Skip for now"

    assert_current_path(%r{\A/matches/#{match.id}})
    visit leaderboard_path
    assert_selector "[data-leaderboard-row=arya].is-you", text: /1\s*W/
    arya = User.find_by!(email: "arya@example.com")
    assert_equal arya, match.reload.winner
    assert_not User.exists?(guest.id)
    screenshot("guest-win-claimed")
  end

  test "a guest who loses gets the gentler line" do
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"
    guest = LiveSeek.last.user
    match = live_result(guest, @qavo, winner: @qavo)

    visit match_path(match)
    within("[data-test=game-over-modal]") do
      assert_text "Sign in to keep this game and your record"
      assert_no_text "live leaderboard"
    end
    screenshot("guest-loss-line")
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/leaderboard-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
