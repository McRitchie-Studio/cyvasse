require "test_helper"

# [integration] Rule change of September 29, 2026 (Alex): elephants move two
# hexes, not three. A live match in play refuses a three-hex elephant move
# posted through the controller, exactly as the board posts it, and accepts a
# two-hex one. The rules change for a match already under way the moment it
# deploys, for both players alike.
#
# Hex numbers are the legacy data-hexIndex, in the home frame: 46 is the
# middle of the board and 47 48 49 run to its right along the middle row.
class ElephantMoveTest < ActionDispatch::IntegrationTest
  include MatchPlay

  ELEPHANT = 6 # the first elephant's army index

  def player_session(user)
    open_session do |session|
      session.post link_consume_path(token: Studio::Link.create_magic_link(email: user.email).token)
    end
  end

  def post_json(session, path, body)
    session.post path, params: body.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    session.response.parsed_body
  end

  # An army with only the named units on the board; the rest are captured.
  def boxed(team, spots)
    CyvasseRules::Game.format((1..19).map { |index| [ index, spots.fetch(index, "g#{team}") ] })
  end

  # A live match between two people, set up and under way, then cut down to a
  # home elephant on 46 with the open middle row ahead of it: home to move.
  def live_match_with_open_elephant
    match = Match.start_live!(@home, @away, rng: Random.new(7))
    match.set_up!(@home, home_lineup)
    match.set_up!(@away, away_lineup)
    match.reload.update_columns(home_units_position: boxed(Match::HOME, ELEPHANT => 46, 17 => 91),
                                away_units_position: boxed(Match::AWAY, 17 => 1), whos_turn: Match::HOME)
    assert match.reload.live?
    assert match.in_progress?
    match
  end

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  test "a live match refuses a three-hex elephant move and accepts a two-hex one" do
    match = live_match_with_open_elephant
    home = player_session(@home)
    turn = match.turn

    body = post_json(home, moves_match_path(match), steps: [ [ 46, 49 ] ])
    home.assert_response :unprocessable_entity
    assert_match "not allowed", body["error"]
    assert_equal turn, match.reload.turn, "the refused move changed nothing"
    assert_equal 46, match.to_game.units.find { |u| u.team == Match::HOME && u.index == ELEPHANT }.hex

    body = post_json(home, moves_match_path(match), steps: [ [ 46, 48 ] ])
    home.assert_response :success
    assert_nil body["error"]
    assert_equal turn + 1, match.reload.turn
    assert_equal 48, match.to_game.units.find { |u| u.team == Match::HOME && u.index == ELEPHANT }.hex
    assert_equal "46,48", match.last_move
  end
end
