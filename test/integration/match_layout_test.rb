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
      assert_select "[data-cyvasse-match-target=opponent]", match.display_name_of(match.away_user)
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
