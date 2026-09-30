require "test_helper"

# [component] The match page's layout (matches/show): the board beside a
# sidebar that opens with the versus card, you over them, then the panel that
# holds the clock, the status, the notices, the links and the controls.
class MatchLayoutTest < ActionDispatch::IntegrationTest
  include MatchPlay

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  test "the versus card comes first, then the board, then the panel, with no row across the top" do
    log_in_as(@home)
    get match_path(started_match(@home, @away))

    assert_select ".match-top", 0
    assert_select "section[data-controller=cyvasse-match] > .match-layout", 1
    children = css_select(".match-layout > *")
    assert_equal 3, children.size
    [ ".match-versus-card", ".cyvasse-board-wrap", "aside.match-panel" ].zip(children).each do |css, node|
      assert node.matches?(css), "expected #{css}, got #{node.name}.#{node['class']}"
    end
    assert_select ".match-layout > .match-versus-card:first-child h1.match-versus", 1
    assert_select ".cyvasse-board-wrap .cyvasse-threat-toggle", 0
  end

  # game.css sizes the pieces per skin ([data-skin] .cyvasse-board): the pencil
  # parchment disc and its size tiers apply on a match only if the page names
  # its skin, as /play does.
  test "the match page names the skin its pieces are drawn in" do
    log_in_as(@home)
    match = started_match(@home, @away)

    get match_path(match, skin: "pencil")
    assert_select "section[data-controller=cyvasse-match][data-skin=pencil]", 1
    get match_path(match)
    assert_select "section[data-controller=cyvasse-match][data-skin=vector]", 1
  end

  test "the versus card stacks you over your opponent, avatar then name, around a vs" do
    log_in_as(@home)
    get match_path(started_match(@home, @away))

    order = css_select(".match-versus-card [data-avatar], .match-versus-card .match-versus-name, .match-versus-card .match-versus-vs")
              .map { |n| n["data-avatar"] ? "avatar" : n.text.squish }
    assert_equal [ "avatar", "arya", "vs", "avatar", "brienne" ], order
    assert_select ".match-versus [data-side=me] + .match-versus-vs + [data-side=them]", 1
    assert_select "[data-side=them] [data-cyvasse-match-target=opponent]", "brienne"
    assert_select ".match-versus-bot", 0
  end

  test "a computer opponent is marked by a quiet caption, not a pill" do
    match = Match.start_live!(@home, computer: true, rng: Random.new(4))
    log_in_as(@home)
    get match_path(match)

    assert_select "h1.match-versus [data-side=them] .match-versus-who" do
      assert_select "[data-cyvasse-match-target=opponent]", match.away_user.player_name
      assert_select ".match-versus-bot", "Computer"
    end
    assert_select ".live-computer-tag", 0
  end

  test "the panel holds the clock, the status, the notices, the links and the controls" do
    match = Match.start_live!(@home, computer: true, rng: Random.new(4))
    log_in_as(@home)
    get match_path(match)

    assert_select "aside.match-panel" do
      assert_select "[data-cyvasse-match-target=clock] [data-cyvasse-match-target=clockBar]"
      assert_select "[data-cyvasse-match-target=status]"
      assert_select "[data-cyvasse-match-target=notice]"
      assert_select "[data-cyvasse-match-target=error]"
      assert_select "[data-match-slot=take-back-seat]"
      assert_select "a[href=?]", matches_path, text: "← My games"
      assert_select "a[href=?]", rules_path, text: "How to play"
      assert_select ".cyvasse-threat-toggle input[data-cyvasse-match-target=threatToggle]", 2
      assert_select "form[action=?] button", match_path(match), text: "Forfeit match"
      assert_select "[data-cyvasse-match-target=graveyard]", 2
    end
    assert_no_match(/Cancel match/, response.body)
  end

  # Task cyvasse-sidebar-reorder: the timer card (clock, then the threat
  # switches), the army card (setup) or the unit card (play), the status
  # line, the fallen card, and last the links and the forfeit.
  SIDEBAR_ORDER = [
    ".match-panel-status", ".cyvasse-setup-controls", "[data-cyvasse-match-target=info]",
    ".match-status-line", "[data-cyvasse-match-target=fallen]", ".match-actions"
  ].freeze

  def assert_sidebar_order
    kids = css_select("aside.match-panel > *")
    at = SIDEBAR_ORDER.map { |css| kids.index { _1.matches?(css) } }
    assert at.none?(&:nil?), "every section renders: #{SIDEBAR_ORDER.zip(at).inspect}"
    assert_equal at.sort, at, "sidebar order: #{SIDEBAR_ORDER.zip(at).inspect}"
    assert kids.last.matches?(".match-actions"), "the links and the forfeit come last"
  end

  test "setup: timer card, then the army card led by its status and Ready, then the status line and the links" do
    match = Match.start_live!(@home, computer: true, rng: Random.new(4))
    log_in_as(@home)
    get match_path(match)

    assert_sidebar_order
    timer = css_select("aside.match-panel > .match-panel-status").sole
    parts = timer.css("[data-cyvasse-match-target=clock], .cyvasse-threat-toggles")
    assert_equal %w[clock toggles], parts.map { _1["data-cyvasse-match-target"] == "clock" ? "clock" : "toggles" }, "the switches sit under the clock"
    assert_empty timer.css("[data-cyvasse-match-target=status]"), "the status line left the timer card"

    army = css_select(".cyvasse-setup-controls > .cyvasse-army").sole
    order = army.css("h2, .cyvasse-army-status, button, .cyvasse-dock").map do |node|
      node.name == "h2" ? "heading" : node["class"][/cyvasse-(army-status|smart|ready|dock)/, 1]
    end
    assert_equal %w[heading army-status smart ready dock], order, "status, then Smart Setup and Ready, above the units"
    copy = army.at_css(".cyvasse-army-status")
    assert_equal "true", copy["aria-hidden"], "the copy is for the eye"
    assert_equal "armyStatus", copy["data-cyvasse-match-target"]

    live = css_select("aside.match-panel [aria-live=polite][data-cyvasse-match-target=status]")
    assert_equal 1, live.size, "one status live region"
    assert live.sole.matches?(".match-status-line")
  end

  test "play: the threat switches in the timer card, the status line under the unit card, the links last" do
    log_in_as(@home)
    get match_path(started_match(@home, @away))

    assert_sidebar_order
    assert_select "aside.match-panel > .match-panel-status .cyvasse-threat-toggles .cyvasse-threat-toggle", 2
    assert_select "aside.match-panel > .match-panel-status .cyvasse-legend", 1
    assert_select ".match-actions .cyvasse-threat-toggles", 0
    assert_select "aside.match-panel > [data-cyvasse-match-target=info] + .match-status-line[role=status]", 1
  end

  test "forfeiting a game in play resigns it, after a confirm" do
    match = started_match(@home, @away)
    log_in_as(@home)
    get match_path(match)

    form = css_select("aside.match-panel form[action='#{resign_match_path(match)}']").sole
    assert_equal "Forfeit match", form.at_css("button").text.strip
    assert_match(/Forfeit this match\? brienne wins\./, form["data-turbo-confirm"])
    assert_select "button", text: "Resign", count: 0
    assert_no_match(/Cancel match/, response.body)
  end

  test "before the game starts, Forfeit match calls it off, after a confirm" do
    match = Match.start_live!(@home, computer: true, rng: Random.new(4))
    log_in_as(@home)
    get match_path(match)

    assert_select "section[data-match-status=?]", match.match_status
    pregame = css_select("aside.match-panel [data-forfeit=pregame] form").sole
    assert_equal match_path(match), pregame["action"]
    assert_equal "delete", pregame.at_css("input[name=_method]")["value"]
    assert_match(/Forfeit this match\?/, pregame["data-turbo-confirm"])
    # The in-play control is there for when the game starts under this page.
    assert_select "aside.match-panel [data-forfeit=play] form[action=?]", resign_match_path(match)
  end
end
