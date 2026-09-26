require "test_helper"

# [integration] Two signed-in players play a whole match through the
# controllers: username, challenge, accept, both setups, every turn to the
# king's capture, as JSON exactly as the board posts it.
class OnlineMatchTest < ActionDispatch::IntegrationTest
  include MatchPlay

  def player_session(user)
    open_session do |session|
      session.post link_consume_path(token: Studio::Link.create_magic_link(email: user.email).token)
    end
  end

  def post_json(session, path, body)
    session.post path, params: body.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    session.response.parsed_body
  end

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  test "a signed-out visitor is sent to sign in" do
    get matches_path
    assert_response :redirect
    assert_no_match %r{/matches}, response.location
  end

  test "a player without a username chooses one, then lands on My games" do
    newcomer = User.create!(email: "new@example.com", name: "Newcomer")
    log_in_as(newcomer)

    get matches_path
    assert_redirected_to username_path(return_to: matches_path)

    patch username_path, params: { username: "no", return_to: matches_path }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /3 to 20/

    patch username_path, params: { username: "newcomer", return_to: "//evil.example/steal" }
    assert_redirected_to matches_path, "an off-site return address is ignored"
    assert_equal "newcomer", newcomer.reload.username
  end

  test "two players complete a match through the controllers" do
    home = player_session(@home)
    away = player_session(@away)

    home.post matches_path, params: { username: "Brienne" }
    match = Match.last
    home.assert_redirected_to match_path(match)

    away.get matches_path
    away.assert_select "[data-section=set-up-your-army] a[href=?]", match_path(match)
    away.post accept_match_path(match)
    away.assert_redirected_to match_path(match)

    assert_equal({}, post_json(home, setup_match_path(match), lineup: home_lineup).except("state"))
    body = post_json(away, setup_match_path(match), lineup: away_lineup)
    assert_equal "play", body.dig("state", "phase")
    assert_equal false, body.dig("state", "your_turn"), "home moves first in the recorded game"

    GAME.fetch("turns").each_with_index do |turn, n|
      mover = turn.fetch("mover") == Match::HOME ? home : away
      body = post_json(mover, moves_match_path(match), steps: steps_for(turn))
      assert_nil body["error"], "turn #{n}"
      mover.assert_response :success
    end

    assert_equal "over", body.dig("state", "phase")
    assert_equal 1, body.dig("state", "winner"), "the away player's own view says they won"
    assert_equal [ Match::FINISHED, "king", @away ], [ match.reload.match_status, match.finish_reason, match.winner ]

    home.get matches_path
    home.assert_select "[data-section=finished] li", /lost \(king captured\)/
    home.assert_select "[data-record]", "0 won, 1 lost"
  end

  test "an illegal or out-of-turn move answers 422 with the true state" do
    match = started_match(@home, @away)
    home = player_session(@home)
    away = player_session(@away)

    body = post_json(away, moves_match_path(match), steps: steps_for(GAME.fetch("turns").first))
    away.assert_response :unprocessable_entity
    assert_match "turn", body["error"]
    assert_equal 1, body.dig("state", "turn")

    body = post_json(home, moves_match_path(match), steps: [ [ 52, 52 ] ])
    home.assert_response :unprocessable_entity
    assert_match "not allowed", body["error"]
    assert_equal 0, ErrorLog.count, "a refused move is an answer, not an error"
  end

  test "a match is private to its two players" do
    match = started_match(@home, @away)
    log_in_as(make_player("cersei"))

    get match_path(match)
    assert_response :not_found
    post moves_match_path(match), params: { steps: [ [ 52, 53 ] ] }, as: :json
    assert_response :not_found
  end

  test "the board page carries the player's own view and the URLs it posts to" do
    match = started_match(@home, @away)
    log_in_as(@away)
    get match_path(match)

    assert_response :success
    assert_select "[data-controller=cyvasse-match][data-cyvasse-match-move-url-value=?]", moves_match_path(match)
    state = JSON.parse(css_select("[data-controller=cyvasse-match]").first["data-cyvasse-match-state-value"])
    assert_equal "away", state["seat"]
    assert_equal 38, state["units"].size
  end

  test "opening My games enforces the seven-day clock" do
    match = started_match(@home, @away)
    log_in_as(@away)

    travel 8.days do
      get matches_path
    end
    assert_equal [ "forfeit", @away ], [ match.reload.finish_reason, match.winner ]
    assert_select "[data-section=finished] li", /won \(out of time\)/
  end

  # A page left open past the opponent's deadline still carries the Resign
  # button. Posting it is refused with the clock's answer, and the resigner
  # keeps the win the clock gave them.
  test "a resign posted from a stale page after the opponent's clock ran out keeps the forfeit win" do
    match = started_match(@home, @away)
    resigner = match.opponent_of(match.user_to_move)
    log_in_as(resigner)

    travel 8.days do
      post resign_match_path(match)
    end
    assert_redirected_to match_path(match)
    assert_match "seven-day clock", flash[:alert]
    assert_equal [ "forfeit", resigner ], [ match.reload.finish_reason, match.winner ]
  end

  test "resigning and declining from the page" do
    match = started_match(@home, @away)
    log_in_as(@home)
    post resign_match_path(match)
    assert_redirected_to match_path(match)
    assert_equal @away, match.reload.winner

    challenge = Match.challenge!(@away, "arya")
    delete match_path(challenge)
    assert_redirected_to matches_path
    assert_not Match.exists?(challenge.id)
  end

  test "challenging an unknown player explains itself" do
    log_in_as(@home)
    post matches_path, params: { username: "ghost" }
    assert_redirected_to matches_path
    follow_redirect!
    assert_match "No player is called ghost", response.body
  end
end
