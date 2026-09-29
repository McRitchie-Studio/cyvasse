require "test_helper"

# [unit] Taking back a seat the computer took over (LiveMatch#take_back_seat!):
# only the seat's own player, only in play, never across a computer move half
# made, and the missed clocks stay counted.
class TakeBackSeatTest < ActiveSupport::TestCase
  include MatchPlay
  include LiveResults
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
    @rng = Random.new(7)
  end

  # A live game in play whose home seat a computer took over, with `to_move`
  # to move and the computer, when it is its turn, still thinking.
  def taken_over_match(to_move:)
    match = Match.start_live!(@home, @away, rng: @rng)
    match.set_up!(@home, home_lineup)
    match.set_up!(@away, away_lineup)
    match.reload.update_columns(home_bot: true, home_strikes: 2, whos_turn: to_move == :home ? Match::HOME : Match::AWAY,
                                clock_started_at: Time.current,
                                bot_due_at: to_move == :home ? 10.seconds.from_now : nil)
    match.reload
  end

  def quiet_turn_for(match)
    game = match.to_game
    from = CyvasseRules::Bot.movers(game).find { |hex| !game.piece_at(hex).type.cavalry? && game.legal_actions(hex).moves.any? }
    steps = [ [ from, game.legal_actions(from).moves.first ] ]
    match.seat_to_move == :away ? steps.map { |s| s.map { mirror(_1) } } : steps
  end

  test "reclaiming a seat hands the turn back to the player" do
    match = taken_over_match(to_move: :away)

    match.take_back_seat!(@home, rng: @rng)
    match.play!(@away, quiet_turn_for(match.reload))

    match.reload
    assert_not match.bot_seat?(:home)
    assert match.your_turn?(@home)
    assert_nil match.bot_due_at, "no computer is scheduled for the seat"
    assert_equal match.clock_started_at + LiveMatch::MOVE_CLOCK_LIVE, match.live_clock_ends_at
    turn = match.turn
    match.play!(@home, quiet_turn_for(match))
    assert_equal turn + 1, match.reload.turn
  end

  test "while the computer thinks for the seat, its move lands first, then the seat is the player's" do
    match = taken_over_match(to_move: :home)
    before = [ match.turn, match.last_move ]

    match.take_back_seat!(@home, rng: @rng)

    match.reload
    assert_not_equal before, [ match.turn, match.last_move ], "the computer's move landed"
    assert_not match.bot_seat?(:home)
    assert_equal :away, match.seat_to_move
    assert match.your_turn?(@away)
  end

  test "the move the computer is already showing is the one that lands" do
    match = taken_over_match(to_move: :home)
    match.update_columns(bot_due_at: nil)
    match.tick!(rng: @rng)
    plan = match.reload.bot_plan["steps"]
    expected = match.to_game.tap { _1.play!(plan) }.position(Match::HOME)

    match.take_back_seat!(@home, rng: Random.new(99))

    assert_equal expected, match.reload.home_units_position
    assert_not match.bot_seat?(:home)
  end

  test "only the seat's own player can take it back" do
    match = taken_over_match(to_move: :away)

    error = assert_raises(Match::Refused) { match.take_back_seat!(@away, rng: @rng) }
    assert_match(/already yours/, error.message)
    stranger = make_player("sansa")
    assert_raises(Match::Refused) { match.take_back_seat!(stranger, rng: @rng) }
    assert match.reload.bot_seat?(:home)
  end

  test "a finished match cannot be taken back" do
    match = taken_over_match(to_move: :away)
    match.resign!(@away)

    assert_raises(Match::Refused) { match.take_back_seat!(@home, rng: @rng) }
  end

  test "the missed clocks stay counted: one more and the computer takes the seat again" do
    match = taken_over_match(to_move: :away)
    match.take_back_seat!(@home, rng: @rng)
    match.play!(@away, quiet_turn_for(match.reload))

    live = match.reload.state_for(@home)[:live]
    assert_equal({ you: true, opponent: false }, live[:took_back])
    assert_equal({ you: false, opponent: false }, live[:taken_over])
    assert_equal({ you: false, opponent: true }, match.state_for(@away)[:live][:took_back])
    assert_equal 2, match.strikes(:home)

    travel 31.seconds do
      match.tick!(rng: @rng)
      assert match.reload.taken_over?(:home)
      assert_equal 3, match.strikes(:home)
    end
  end

  test "a reclaimed seat counts for the player again, on the record and the leaderboard" do
    match = taken_over_match(to_move: :away)
    match.take_back_seat!(@home, rng: @rng)
    match.reload.resign!(@away)

    assert_equal [ 1, 0 ], [ @home.reload.wins, @home.losses ]
    row = Leaderboard.rank_for(@home)
    assert_equal [ 1, 1, Leaderboard::WIN_POINTS ], [ row.games, row.wins, row.points ]
    assert match.reload.state_for(@home)[:live][:board_win]
  end
end
