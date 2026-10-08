require "test_helper"

# [integration] "Forfeit match" through real requests (task
# cyvasse-forfeit-match-answers-500). Before play it calls the match off
# (DELETE /matches/:id); in play it resigns (POST /matches/:id/resign). A
# match made by Play Now is pointed at by its players' searches (LiveSeek),
# and calling one off answered a 500 on that foreign key.
class ForfeitMatchTest < ActionDispatch::IntegrationTest
  include MatchPlay

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  def play_now(session)
    session.post live_seeks_path
    LiveSeek.order(:id).last
  end

  test "forfeiting a Play Now match against a computer player during setup calls it off" do
    log_in_as(@home)
    seek = play_now(self)
    post computer_live_seek_path(seek)
    match = seek.reload.match
    assert match.pregame?
    opponent = match.away_user

    get match_path(match)
    assert_select "[data-forfeit=pregame] form[action=?]", match_path(match)

    delete match_path(match)
    assert_redirected_to matches_path
    assert_equal "Match against #{opponent.player_name} cancelled.", flash[:notice]
    assert_not Match.exists?(match.id)
    assert_not LiveSeek.exists?(seek.id), "the search that made the match goes with it, so it cannot start another"
    assert_equal [ 0, 0 ], [ @home.reload.wins, @home.losses ]

    # A double click's second request finds nothing to forfeit.
    delete match_path(match)
    assert_response :not_found
  end

  test "forfeiting a Play Now match between two players during setup calls it off for both" do
    arya = open_session
    arya.post link_consume_path(token: Studio::Link.create_magic_link(email: @home.email).token)
    brienne = open_session
    brienne.post link_consume_path(token: Studio::Link.create_magic_link(email: @away.email).token)
    arya_seek = play_now(arya)
    brienne_seek = play_now(brienne)
    match = brienne_seek.reload.match
    assert_equal match, arya_seek.reload.match

    brienne.delete match_path(match)
    brienne.assert_redirected_to matches_path
    assert_not Match.exists?(match.id)
    assert_empty LiveSeek.where(id: [ arya_seek.id, brienne_seek.id ])

    # The other player's open board asks for the state and learns it is gone.
    arya.get match_path(match, format: :json)
    arya.assert_response :not_found
    arya.get matches_path
    arya.assert_response :success
  end

  test "forfeiting a match in play, as the player to move or the other, gives the opponent the win once" do
    2.times do |n|
      match = started_match(@home, @away)
      forfeiter = n.zero? ? match.user_to_move : match.opponent_of(match.user_to_move)
      winner = match.opponent_of(forfeiter)
      log_in_as(forfeiter)

      assert_difference -> { winner.reload.wins } => 1, -> { forfeiter.reload.losses } => 1 do
        post resign_match_path(match)
        assert_redirected_to match_path(match)
        assert_equal "You resigned.", flash[:notice]

        # A second request is refused with a reason and changes nothing.
        post resign_match_path(match)
        assert_redirected_to match_path(match)
        assert_equal "Only a match in play can be resigned.", flash[:alert]
        delete match_path(match)
        assert_redirected_to match_path(match)
        assert_equal "A match in play can only be resigned.", flash[:alert]
      end
      assert_equal [ Match::FINISHED, "resigned", winner ], [ match.reload.match_status, match.finish_reason, match.winner ]

      # The opponent's board reads the result on its next poll.
      log_in_as(winner)
      get match_path(match, format: :json)
      assert_equal [ "over", "resigned" ], response.parsed_body.values_at("phase", "finish_reason")
    end
  end

  test "a match that is not yours, or no session, is refused without a 500" do
    match = started_match(@home, @away)
    log_in_as(make_player("cersei"))
    post resign_match_path(match)
    assert_response :not_found
    delete match_path(match)
    assert_response :not_found

    reset!
    post resign_match_path(match)
    assert_redirected_to "/login"
    delete match_path(match)
    assert_redirected_to "/login"
    assert match.reload.in_progress?
  end
end
