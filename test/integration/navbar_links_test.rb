require "test_helper"

# [integration] The navbar links over real requests: the Leaderboard badge is
# Leaderboard.rank_for's rank for a signed-in player and for a Play Now guest,
# My games shows only for a player with a username, and an engine page (the
# sign-in page) renders the links from the engine's own controller.
class NavbarLinksIntegrationTest < ActionDispatch::IntegrationTest
  include LiveResults

  NAV = "nav[aria-label=Main]".freeze

  def board_link = css_select("#{NAV} a[href='/leaderboard']").first

  test "a signed-in player's badge is their live rank, on every page" do
    arya, brienne = player("arya"), player("brienne")
    live_result(arya, brienne, winner: arya)
    log_in_as(brienne)

    [ root_path, leaderboard_path, matches_path ].each do |path|
      get path
      assert_response :success
      assert_select "#{NAV} a[href='/leaderboard']", count: 2, text: /\ALeaderboard\s*##{Leaderboard.rank_for(brienne).rank}\z/
      assert_select "#{NAV} a[href='/matches']", count: 2, text: "My games"
    end
    assert_equal "#2", board_link.at_css("span").text
  end

  test "the badge follows the board when the rank changes" do
    arya, brienne = player("arya"), player("brienne")
    live_result(arya, brienne, winner: arya)
    log_in_as(brienne)
    get root_path
    assert_equal "#2", board_link.at_css("span").text

    2.times { live_result(brienne, arya, winner: brienne) }
    get root_path
    assert_equal "#1", board_link.at_css("span").text
  end

  test "a Play Now guest on the board sees their rank under the guest name" do
    post live_seeks_path
    guest = LiveSeek.last.user
    live_result(guest, computer, winner: guest)

    get leaderboard_path
    assert_select "#{NAV} a[href='/leaderboard'][aria-current=page]", count: 2, text: /#1/
    assert_select "#{NAV} a[href='/matches']", 2
  end

  test "a signed-out visitor sees the Leaderboard with no badge and no My games" do
    get root_path
    assert_select "#{NAV} a[href='/leaderboard']", count: 2, text: "Leaderboard"
    assert_select "#{NAV} a[href='/matches']", 0
  end

  test "the engine's sign-in page renders the links too" do
    get login_path
    assert_response :success
    assert_select "#{NAV} a[href='/leaderboard']", 2
  end
end
