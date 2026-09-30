require "test_helper"

# [integration] Rule changes of September 29, 2026 (Alex, task
# cyvasse-stats-and-trumps-v3): trumps work on offense only, range units
# defend at 1, cavalry jump light horse 4 + 1 and heavy horse 3 + 1, and the
# catapult moves 1. A live match already in play takes the new rules the
# moment they deploy: the server accepts the captures the new rules allow and
# refuses, with a 422 and nothing changed, the moves only the old rules
# allowed. Every step is posted through the controller as the board posts it.
#
# Hex numbers are the legacy data-hexIndex, in the home frame: 46 is the
# middle of the board and 47 48 49 50 51 run to its right along the middle row.
class OffenseOnlyTrumpsTest < ActionDispatch::IntegrationTest
  include MatchPlay

  # Army indices (CyvasseRules::Units::ARMY, 1-based).
  SPEARMAN = 4
  ELEPHANT = 6
  LIGHT_HORSE = 8
  CROSSBOWMAN = 12
  TREBUCHET = 14
  CATAPULT = 15
  DRAGON = 16
  KING = 17

  def player_session(user)
    open_session do |session|
      session.post link_consume_path(token: Studio::Link.create_magic_link(email: user.email).token)
    end
  end

  def post_json(session, path, body)
    session.post path, params: body.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    session.response.parsed_body
  end

  def boxed(team, spots)
    CyvasseRules::Game.format((1..19).map { |index| [ index, spots.fetch(index, "g#{team}") ] })
  end

  # A live match under way, cut down to the given units with the kings far
  # apart (home on 91, away on 1): home to move.
  def live_match(home:, away:)
    match = Match.start_live!(@home, @away, rng: Random.new(7))
    match.set_up!(@home, home_lineup)
    match.set_up!(@away, away_lineup)
    match.reload.update_columns(home_units_position: boxed(Match::HOME, home.merge(KING => 91)),
                                away_units_position: boxed(Match::AWAY, away.merge(KING => 1)), whos_turn: Match::HOME)
    assert match.reload.live?
    assert match.in_progress?
    match
  end

  def unit(match, team, index) = match.to_game.units.find { |u| u.team == team && u.index == index }

  def assert_refused(session, match, steps)
    turn = match.reload.turn
    body = post_json(session, moves_match_path(match), steps:)
    session.assert_response :unprocessable_entity
    assert_match "not allowed", body["error"]
    assert_equal turn, match.reload.turn, "the refused move #{steps.inspect} changed nothing"
  end

  def assert_played(session, match, steps)
    turn = match.reload.turn
    body = post_json(session, moves_match_path(match), steps:)
    session.assert_response :success
    assert_nil body["error"]
    assert_equal turn + 1, match.reload.turn
  end

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
    @session = player_session(@home)
  end

  test "a dragon takes the trebuchet that trumps it: the trump no longer protects" do
    match = live_match(home: { DRAGON => 46 }, away: { TREBUCHET => 50 })
    assert_played(@session, match, [ [ 46, 50 ] ])
    assert_equal "dead", unit(match, Match::AWAY, TREBUCHET).status.to_s
    assert_equal 50, unit(match, Match::HOME, DRAGON).hex
  end

  test "a trebuchet takes a dragon when it attacks, and stays put" do
    match = live_match(home: { TREBUCHET => 46 }, away: { DRAGON => 50 })
    assert_played(@session, match, [ [ 46, 50 ] ])
    assert_equal "dead", unit(match, Match::AWAY, DRAGON).status.to_s
    assert_equal 46, unit(match, Match::HOME, TREBUCHET).hex
  end

  test "an elephant takes a crossbowman, which defends at 1 and trumps nothing" do
    match = live_match(home: { ELEPHANT => 46 }, away: { CROSSBOWMAN => 47 })
    assert_played(@session, match, [ [ 46, 47 ] ])
    assert_equal "dead", unit(match, Match::AWAY, CROSSBOWMAN).status.to_s
  end

  test "the old trebuchet trump over the spearman is refused" do
    match = live_match(home: { TREBUCHET => 46 }, away: { SPEARMAN => 50 })
    assert_refused(@session, match, [ [ 46, 50 ] ])
    assert_equal 50, unit(match, Match::AWAY, SPEARMAN).hex
  end

  test "a spearman no longer takes an elephant" do
    match = live_match(home: { SPEARMAN => 46 }, away: { ELEPHANT => 47 })
    assert_refused(@session, match, [ [ 46, 47 ] ])
  end

  test "a light horse jumps 4 then 1: the old second jump of 2 is refused" do
    match = live_match(home: { LIGHT_HORSE => 46 }, away: {})
    assert_refused(@session, match, [ [ 46, 49 ], [ 49, 51 ] ])
    assert_played(@session, match, [ [ 46, 50 ], [ 50, 51 ] ])
    assert_equal 51, unit(match, Match::HOME, LIGHT_HORSE).hex
  end

  test "a catapult moves 1: the old move of 2 is refused" do
    match = live_match(home: { CATAPULT => 46 }, away: {})
    assert_refused(@session, match, [ [ 46, 48 ] ])
    assert_played(@session, match, [ [ 46, 47 ] ])
  end
end
