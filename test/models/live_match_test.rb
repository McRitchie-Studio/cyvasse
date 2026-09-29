require "test_helper"

# [integration] Live matches (LiveMatch), clocks driven by travel_to: the 60s
# setup clock, the 30s move clock, strikes, the computer taking a seat after
# two missed clocks, and a computer opponent that sets up at once and plays
# each turn in paced steps (select, move, second jump).
class LiveMatchTest < ActiveSupport::TestCase
  include MatchPlay
  include LiveBot
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
    @rng = Random.new(7)
  end

  def seat_to_move_user(match)
    match.seat_to_move == :home ? match.home_user : match.away_user
  end

  # A quiet legal turn for the side to move (one step, no capture, no
  # cavalry), from the mover's own seat: keeps a test's game from ending.
  def quiet_turn_for(match)
    game = match.to_game
    from = CyvasseRules::Bot.movers(game).find { |hex| !game.piece_at(hex).type.cavalry? && game.legal_actions(hex).moves.any? }
    steps = [ [ from, game.legal_actions(from).moves.first ] ]
    match.seat_to_move == :away ? steps.map { |s| s.map { mirror(_1) } } : steps
  end

  # A legal turn for the side to move, from the mover's own seat.
  def turn_for(match)
    steps = CyvasseRules::Bot.choose_turn(match.to_game, rng: Random.new(3))
    match.seat_to_move == :away ? steps.map { |s| s.map { mirror(_1) } } : steps
  end

  test "a match against the computer seats a named computer player who sets up at once" do
    match = Match.start_live!(@home, computer: true, rng: @rng)

    assert match.live?
    assert match.away_user.computer?
    assert_includes LiveMatch::COMPUTER_NAMES.values, match.display_name_of(match.away_user)
    assert match.away_ready?
    assert_not match.home_ready?
    assert_equal Match::ACCEPTED, match.match_status
    assert_equal 0, Studio::EmailDelivery.count, "live matches send no mail"
  end

  test "nothing happens before the setup clock runs out" do
    match = Match.start_live!(@home, @away, rng: @rng)
    travel 59.seconds do
      match.tick!(rng: @rng)
      assert_not match.reload.home_ready?
      assert_equal [ 0, 0 ], [ match.home_strikes, match.away_strikes ]
    end
  end

  test "a missed setup clock places a random army, counts a strike and starts the game" do
    match = Match.start_live!(@home, @away, rng: @rng)
    match.set_up!(@home, home_lineup)
    travel 61.seconds do
      match.tick!(rng: @rng)
      match.reload
      assert match.in_progress?
      assert match.away_auto_set_up?
      assert_not match.home_auto_set_up?
      assert_equal [ 0, 1 ], [ match.home_strikes, match.away_strikes ]
      assert_in_delta Time.current, match.clock_started_at, 1
    end
  end

  test "a missed move clock plays a computer move for the player and counts a strike" do
    match = Match.start_live!(@home, @away, rng: @rng)
    match.set_up!(@home, home_lineup)
    match.set_up!(@away, away_lineup)
    seat = match.reload.seat_to_move
    turn = match.turn
    travel 31.seconds do
      match.tick!(rng: @rng)
      match.reload
      assert_equal turn + 1, match.turn, "the late player's move was made for them"
      assert_equal 1, match.strikes(seat)
      assert_not match.bot_seat?(seat), "one strike is a warning, not a replacement"
    end
  end

  test "two missed clocks hand the seat to a computer player, who then plays it" do
    match = Match.start_live!(@home, @away, rng: @rng)
    match.set_up!(@home, home_lineup)
    match.set_up!(@away, away_lineup)
    late = match.reload.seat_to_move
    late_user = seat_to_move_user(match)

    travel 31.seconds
    match.tick!(rng: @rng)
    match.play!(seat_to_move_user(match.reload), quiet_turn_for(match)) # the other player moves in time
    travel 31.seconds
    match.tick!(rng: @rng)

    match.reload
    assert match.taken_over?(late)
    assert_equal 2, match.strikes(late)
    error = assert_raises(Match::Refused) { match.play!(late_user, [ [ 60, 61 ] ]) } if match.in_progress? && match.seat_to_move == late
    assert_match(/computer player has taken your seat/, error.message) if error
  ensure
    travel_back
  end

  # A computer match with the computer to move, paced as in production.
  def computer_to_move
    LiveMatch.bot_pace = 1
    match = Match.start_live!(@home, computer: true, rng: @rng)
    match.set_up!(@home, home_lineup)
    match.reload
    match.play!(@home, quiet_turn_for(match)) if match.in_progress? && match.seat_to_move == :home
    match.reload
    assert_equal :away, match.seat_to_move
    match
  end

  # travel_to drops sub-seconds, so land a second past the step's due time.
  def at_bot_due(match, &block)
    due = match.reload.bot_due_at
    travel_to(due + 1) do
      match.tick!(rng: @rng)
      block.call(match.reload, due)
    end
  end

  teardown { LiveMatch.bot_pace = 0 }

  test "[unit] the computer's pacing draws select, move and second-jump delays in range, and none at pace 0" do
    match = computer_to_move
    20.times do |n|
      match.send(:schedule_bot, Random.new(n))
      assert_includes LiveMatch::BOT_PACING[:select], (match.bot_due_at - Time.current).round(3)
      assert_includes LiveMatch::BOT_PACING[:move], match.bot_plan["move"]
      assert_includes LiveMatch::BOT_PACING[:second], match.bot_plan["second"]
    end
    assert_equal({ select: 2.0..5.0, move: 3.0..5.0, second: 2.0..3.0 }, LiveMatch::BOT_PACING)

    LiveMatch.bot_pace = 0
    freeze_time do
      match.send(:schedule_bot, Random.new(1))
      assert_equal Time.current, match.bot_due_at
      assert_equal [ 0.0, 0.0 ], match.bot_plan.values_at("move", "second")
    end
  end

  test "[integration] a computer selects its unit, then moves it, and the player's clock starts only when it lands" do
    match = computer_to_move
    match.update!(bot_plan: match.bot_plan.merge("steps" => quiet_turn_for(match).map { |st| st.map { mirror(_1) } }))
    steps = match.bot_plan["steps"]
    before = match.last_move
    state = match.state_for(@home)
    assert_nil state[:live][:bot_selected], "nothing is shown while it thinks"
    assert state[:live][:thinking]
    assert_nil state[:live][:clock], "the computer's thinking runs no clock"

    at_bot_due(match) do |m, due|
      assert_equal "selected", m.bot_plan["stage"]
      assert_equal steps.first.first, m.state_for(@home)[:live][:bot_selected], "the unit it will move is shown"
      assert_equal before, m.last_move, "not moved yet"
      assert_nil m.live_clock_ends_at
      assert_in_delta m.bot_plan["move"], m.bot_due_at - due, 0.001, "the move is due its pause after the selection"
    end

    at_bot_due(match) do |m|
      assert_equal steps.first.join(","), m.last_move, "then it moves that unit"
      assert_nil m.bot_plan
      next if m.finished?

      assert_equal :home, m.seat_to_move
      assert_equal Time.current, m.clock_started_at, "the player's clock starts when the move lands"
      assert_nil m.state_for(@home)[:live][:bot_selected]
    end
  end

  test "[integration] a cavalry unit's second jump follows its first after another pause" do
    match = plan_double_jump(computer_to_move)
    first, second = match.bot_plan["steps"]
    turn = match.turn

    at_bot_due(match) { |m| assert_equal "selected", m.bot_plan["stage"] }
    at_bot_due(match) do |m, due|
      assert_equal "moved", m.bot_plan["stage"]
      assert_equal turn, m.turn, "the turn is not played until its last step"
      state = m.state_for(@home)
      assert_equal first, state[:last_move], "the first jump is on the board"
      assert_equal first.last, state[:live][:bot_selected], "and the unit is shown again"
      assert_equal 2, state[:live][:bot_jump]
      assert state[:units].any? { |team, _, hex| team.zero? && hex == first.last }
      assert_in_delta m.bot_plan["second"], m.bot_due_at - due, 0.001, "the second jump waits its own pause"
      assert_nil m.live_clock_ends_at
    end
    at_bot_due(match) do |m|
      assert_equal second.join(","), m.last_move, "then the second jump"
      assert_nil m.bot_plan
    end
  end

  test "[integration] a late poll catches a whole computer turn up at once" do
    match = computer_to_move
    before = match.last_move
    travel 20.seconds do
      match.tick!(rng: @rng)
      assert_not_equal before, match.reload.last_move
      assert_nil match.bot_plan
    end
  end

  test "the live state tells each board its clock, who is thinking and who is a computer" do
    match = Match.start_live!(@home, computer: true, rng: @rng)
    live = match.state_for(@home)[:live]

    assert_equal "setup", live[:clock][:kind]
    assert_equal 60, live[:clock][:seconds]
    assert_equal 10, live[:clock][:warning]
    assert live[:computer]
    assert_equal match.display_name_of(match.away_user), match.state_for(@home)[:opponent][:username]
    assert_nil Match.challenge!(@home, "brienne").state_for(@home)[:live], "an ordinary match has no live state"
  end

  test "just_ended holds for five minutes after the end, so an old match opens without the modal" do
    match = Match.start_live!(@home, computer: true, rng: @rng)
    match.set_up!(@home, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    assert_not match.reload.state_for(@home)[:live][:just_ended], "not while in play"

    match.resign!(@home)
    assert match.state_for(@home)[:live][:just_ended]
    travel(4.minutes) { assert match.state_for(@home)[:live][:just_ended] }
    travel(6.minutes) { assert_not match.state_for(@home)[:live][:just_ended] }
  end

  test "tick! leaves an ordinary match alone" do
    match = started_match(@home, @away)
    before = match.reload.attributes
    travel 1.hour do
      match.tick!
      assert_equal before, match.reload.attributes
    end
  end
end
