require "test_helper"

# [component] The engine navbar (layouts/_navbar) with Cyvasse's links: My
# games and Leaderboard in the desktop bar and the phone row, the Leaderboard
# carrying the player's rank as a badge, and no badge for an unranked player.
class NavbarLinksViewTest < ActionView::TestCase
  include LiveResults

  # The navbar's link rows (desktop bar and phone row); the slide-out sidebar
  # carries its own /leaderboard link.
  NAV = "nav[aria-label=Main]".freeze

  def render_navbar_for(user, path: "/")
    view.define_singleton_method(:current_user) { user }
    view.define_singleton_method(:logged_in?) { user.present? }
    controller.request.path = path
    render partial: "layouts/navbar"
  end

  test "a ranked player sees My games and Leaderboard with the rank, in both rows" do
    arya, brienne = player("arya"), player("brienne")
    live_result(arya, brienne, winner: arya)
    render_navbar_for(brienne)

    assert_select NAV, 2 do |navs|
      navs.each do |nav|
        assert_select nav, "a[href='/matches']", text: "My games"
        assert_select nav, "a[href='/leaderboard']", text: /\ALeaderboard\s*#2\z/
      end
    end
  end

  test "an unranked player sees the Leaderboard with no badge" do
    render_navbar_for(player("arya"))

    assert_select "#{NAV} a[href='/leaderboard']", count: 2, text: /\ALeaderboard\z/
    assert_select "#{NAV} a[href='/leaderboard'] span", 0
  end

  test "a signed-out visitor sees the Leaderboard and no My games" do
    render_navbar_for(nil)

    assert_select "#{NAV} a[href='/leaderboard']", 2
    assert_select "#{NAV} a[href='/matches']", 0
  end

  test "the page's own link is marked current" do
    render_navbar_for(player("arya"), path: "/leaderboard")

    assert_select "#{NAV} a[href='/leaderboard'][aria-current=page]", 2
    assert_select "#{NAV} a[href='/matches']", 2
    assert_select "#{NAV} a[href='/matches'][aria-current]", 0
  end
  # [component] After a game the match page writes the new rank into the
  # navbar (cyvasse/game_over refreshNavRank, production UX audit #14). Its
  # selector finds both rows' Leaderboard links in this navbar, and the badge
  # it adds for a newly ranked player is the engine's own.
  test "the game-over rank refresh finds both Leaderboard links and draws the engine's badge" do
    arya, brienne = player("arya"), player("brienne")
    live_result(arya, brienne, winner: arya)
    render_navbar_for(brienne)

    js = Rails.root.join("app/javascript/cyvasse/game_over.js").read
    selector = js[/NAV_LEADERBOARD = "([^"]+)"/, 1]
    assert_equal "header[data-pin=nav] a[href='/leaderboard']", selector
    links = css_select(selector)
    assert_equal 2, links.size, "the desktop bar and the phone row"
    links.each { |a| assert_equal "#2", a.at_css("span").text }

    badge_class = js[/NAV_BADGE_CLASS = ((?:"[^"]*"\s*\+?\s*)+)/m, 1].scan(/"([^"]*)"/).join
    assert_equal StudioNavbarHelper::NAVBAR_BADGE_CLASS, badge_class
  end
end
