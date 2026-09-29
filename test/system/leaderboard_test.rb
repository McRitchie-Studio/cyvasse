require "application_system_test_case"

# [e2e] The leaderboards and a guest's sign-in after a live game, in a real
# browser: the landing page's live leaderboard card (and its empty state) at
# desktop and phone width, the full board's tabs, the "You won!" call on a
# guest's finished live match, and signing in through the email link to put
# the win on the board. SCREENSHOTS=1 saves each step to tmp/screenshots.
class LeaderboardSystemTest < ApplicationSystemTestCase
  include LiveResults

  setup do
    @qavo = computer
  end

  test "the landing page's card invites the first player when the board is empty" do
    visit root_path
    within("[data-leaderboard-card]") do
      assert_text "LIVE LEADERBOARD"
      assert_button "Be the first on the board — Play Now"
    end
    screenshot("landing-empty")
  end

  test "the landing card lists the leaders and fits a 375px phone" do
    long = player("a_very_long_username")
    arya = player("arya")
    3.times { live_result(long, @qavo, winner: long) }
    live_result(arya, @qavo, winner: arya)

    visit root_path
    assert_equal %w[a_very_long_username arya], all("[data-leaderboard-card] [data-leaderboard-row]").map { _1["data-leaderboard-row"] }
    screenshot("landing-desktop")

    page.driver.browser.manage.window.resize_to(375, 900)
    visit root_path
    assert_selector "[data-leaderboard-card] [data-leaderboard-row]", count: 2
    widths = page_widths
    assert_operator widths.first, :<=, widths.last, "no sideways scroll at phone width"
    screenshot("landing-phone")

    click_on "See all"
    assert_selector "h1", text: "Leaderboard"
    assert_selector "[data-board=live] [data-leaderboard-row=a_very_long_username]", text: /3\s*W/
    widths = page_widths
    assert_operator widths.first, :<=, widths.last, "no sideways scroll at phone width"
    screenshot("leaderboard-phone")
  end

  test "a guest who wins is asked to sign in, and the win lands on the board" do
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"
    guest = LiveSeek.last.user
    match = live_result(guest, @qavo, winner: guest)

    visit match_path(match)
    assert_text "You captured the king. You win."
    assert_selector "[data-cyvasse-match-target=claimWin]", text: "You won!"
    assert_no_selector "[data-cyvasse-match-target=claimLoss]", visible: true
    screenshot("guest-win-cta")

    click_on "Sign in to put this win on the leaderboard"
    assert_selector "h1", text: "Put your win on the leaderboard"
    fill_in "Email", with: "arya@example.com"
    click_on "Email me a sign-in link"
    assert_text "Check your inbox"

    visit link_path(token: Studio::Link.last.token)
    assert_selector "h1", text: "Your username"
    fill_in "Username", with: "arya"
    click_on "Save"

    assert_selector "h1", text: "Leaderboard"
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
    assert_selector "[data-cyvasse-match-target=claimLoss]", text: "Sign in to save your games"
    assert_no_selector "[data-cyvasse-match-target=claimWin]", visible: true
    screenshot("guest-loss-line")
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/leaderboard-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
