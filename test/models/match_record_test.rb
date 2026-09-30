require "test_helper"

# [unit] The won/lost record (Match#finish!, Match#on_record?): a result goes
# on a player's record only when a person played the seat. A computer player
# never gains a win or a loss, and nor does a live seat a computer took over
# after missed clocks. The finish time is stamped for the leaderboard.
class MatchRecordTest < ActiveSupport::TestCase
  include MatchPlay
  include LiveResults

  setup do
    @arya = player("arya")
    @brienne = player("brienne")
  end

  def record(user) = [ user.reload.wins, user.losses ]

  def in_play(match)
    match.update_columns(match_status: Match::IN_PROGRESS, whos_turn: Match::HOME, time_of_last_move: Time.current)
    match
  end

  test "a player who resigns to a computer player takes the loss; the computer gains nothing" do
    match = in_play(Match.start_live!(@arya, computer: true, rng: Random.new(4)))
    qavo = match.away_user
    before = record(qavo)

    freeze_time do
      match.resign!(@arya)
      assert_equal Time.current, match.reload.finished_at
    end
    assert_equal qavo, match.winner
    assert_equal [ 0, 1 ], record(@arya)
    assert_equal before, record(qavo)
  end

  test "beating a computer player is a win on the record, and the computer takes no loss" do
    match = in_play(Match.start_live!(@arya, computer: true, rng: Random.new(4)))
    qavo = match.away_user
    before = record(qavo)
    match.update_columns(whos_turn: Match::AWAY, time_of_last_move: 8.days.ago)

    match.expire!
    assert_equal [ @arya, "forfeit" ], [ match.reload.winner, match.finish_reason ]
    assert_equal [ 1, 0 ], record(@arya)
    assert_equal before, record(qavo)
  end

  test "a win by a stand-in in a taken-over seat is nobody's; the human who lost to it still loses" do
    match = in_play(Match.start_live!(@arya, @brienne, rng: Random.new(4)))
    match.update_columns(home_bot: true, home_strikes: 2)

    match.resign!(@brienne)
    assert_equal @arya, match.reload.winner
    assert_equal [ 0, 0 ], record(@arya)
    assert_equal [ 0, 1 ], record(@brienne)
  end

  test "a loss in a taken-over seat is nobody's either" do
    match = in_play(Match.start_live!(@arya, @brienne, rng: Random.new(4)))
    match.update_columns(home_bot: true, home_strikes: 2, whos_turn: Match::HOME, time_of_last_move: 8.days.ago)

    match.expire!
    assert_equal @brienne, match.reload.winner
    assert_equal [ 0, 0 ], record(@arya)
    assert_equal [ 1, 0 ], record(@brienne)
  end

  test "outside live play the bot flags mean nothing: both players' results count" do
    match = started_match(@arya, @brienne)
    match.update_columns(home_bot: true, home_strikes: 2)

    match.resign!(@brienne)
    assert_equal [ 1, 0 ], record(@arya)
    assert_equal [ 0, 1 ], record(@brienne)
  end

  test "the live state tells a guest whether their win goes on the leaderboard" do
    guest = User.create_guest!(rng: Random.new(8))
    qavo = computer
    won = live_result(guest, qavo, winner: guest)
    lost = live_result(guest, qavo, winner: qavo)
    stand_in = live_result(guest, @arya, winner: guest, home_bot: true, home_strikes: 2)

    assert_equal true, won.state_for(guest)[:live][:board_win]
    assert_equal true, won.state_for(guest)[:you][:guest]
    assert_equal false, lost.state_for(guest)[:live][:board_win]
    assert_equal false, stand_in.state_for(guest)[:live][:board_win]
    assert_equal false, won.state_for(qavo)[:live][:board_win]
  end
  test "the live state tells the game-over modal the points this game earned, and a player's new rank" do
    qavo = computer
    won = live_result(@arya, qavo, winner: @arya)
    lost = live_result(@arya, @brienne, winner: @brienne)
    drawn = live_result(@brienne, @arya, winner: nil)
    stand_in = live_result(@arya, @brienne, winner: @arya, home_bot: true, home_strikes: 2)
    expired = live_result(@arya, @brienne, winner: nil, finish_reason: "expired")

    assert_equal [ 3, 1, 1, 0, nil ], [ won, lost, drawn, stand_in, expired ].map { _1.state_for(@arya)[:live][:board_points] }
    assert_equal 3, lost.state_for(@brienne)[:live][:board_points]
    assert_equal 0, won.state_for(qavo)[:live][:board_points], "a computer player's seat counts for nobody"
    assert_equal Leaderboard.rank_for(@arya).rank, won.state_for(@arya)[:live][:board_rank]
    assert_nil stand_in.state_for(@arya)[:live][:board_rank], "no rank line under a game that earned nothing"
  end

  test "the game's points are the leaderboard's: a player's row sums them" do
    qavo = computer
    matches = [
      live_result(@arya, qavo, winner: @arya), live_result(@arya, @brienne, winner: @brienne),
      live_result(@brienne, @arya, winner: nil), live_result(@arya, @brienne, winner: @arya, home_bot: true, home_strikes: 2)
    ]

    assert_equal Leaderboard.rank_for(@arya).points, matches.sum { _1.state_for(@arya)[:live][:board_points].to_i }
    assert_equal Leaderboard.rank_for(@brienne).points, matches.sum { _1.state_for(@brienne)[:live][:board_points].to_i }
  end

  test "a guest's win earns its points but no rank line: they are asked to sign in instead" do
    guest = User.create_guest!(rng: Random.new(8))
    live = live_result(guest, computer, winner: guest).state_for(guest)[:live]

    assert_equal 3, live[:board_points]
    assert_nil live[:board_rank]
  end
end
