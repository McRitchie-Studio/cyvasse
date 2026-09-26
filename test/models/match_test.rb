require "test_helper"

# [unit] The match state machine: challenge, accept, setup, turn order, the
# win, resigning, and the seven-day clock with its forfeit.
class MatchTest < ActiveSupport::TestCase
  include MatchPlay

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  def mail_keys
    Studio::EmailDelivery.order(:id).map { |d| [ d.email_key, d.to ] }
  end

  # ---- Challenge and accept ----

  test "a challenge by username opens a pending match and mails the challenged player" do
    match = Match.challenge!(@home, "BRIENNE")

    assert_equal Match::PENDING, match.match_status
    assert_equal [ @home, @away ], [ match.home_user, match.away_user ]
    assert_equal "human", match.match_against
    assert_in_delta Time.current, match.time_of_last_move, 5
    assert_equal [ [ "MatchMailer#challenged", "brienne@example.com" ] ], mail_keys
  end

  test "a challenge is refused for a stranger, yourself, or a second open challenge" do
    assert_raises(Match::Refused) { Match.challenge!(@home, "nobody") }
    assert_raises(Match::Refused) { Match.challenge!(@home, "") }
    assert_raises(Match::Refused) { Match.challenge!(@home, "arya") }
    Match.challenge!(@home, "brienne")
    error = assert_raises(Match::Refused) { Match.challenge!(@home, "brienne") }
    assert_match "already challenged", error.message
    assert Match.challenge!(@away, "arya"), "the other way round is a different challenge"
  end

  test "only the challenged player accepts, once" do
    match = Match.challenge!(@home, "brienne")
    assert_raises(Match::Refused) { match.accept!(@home) }
    assert_raises(Match::Refused) { match.accept!(make_player("cersei")) }
    match.accept!(@away)
    assert_equal Match::ACCEPTED, match.reload.match_status
    assert_raises(Match::Refused) { match.accept!(@away) }
  end

  test "a challenge can be declined or withdrawn before play, and then it is gone" do
    declined = Match.challenge!(@home, "brienne")
    declined.withdraw!(@away)
    assert_not Match.exists?(declined.id)

    withdrawn = Match.challenge!(@home, "brienne")
    withdrawn.withdraw!(@home)
    assert_not Match.exists?(withdrawn.id)

    started = started_match(@home, @away)
    assert_raises(Match::Refused) { started.withdraw!(@home) }
  end

  # ---- Setup ----

  test "the challenger may set up at once; the challenged player accepts first" do
    match = Match.challenge!(@home, "brienne")
    match.set_up!(@home, home_lineup)
    assert match.reload.home_ready
    assert_equal Match::PENDING, match.match_status, "one army does not start a game"

    error = assert_raises(Match::Refused) { match.set_up!(@away, away_lineup) }
    assert_match "Accept", error.message
  end

  test "an army is checked, locked once submitted, and the away army stored turned round" do
    match = Match.challenge!(@home, "brienne")
    match.accept!(@away)

    assert_raises(Match::Refused) { match.set_up!(@away, "1:52|") }
    assert_raises(Match::Refused) { match.set_up!(@away, away_lineup.sub(/\|(\d+):\d+\|/) { "|#{$1}:10|" }) }
    assert_not match.reload.away_ready

    match.set_up!(@away, away_lineup)
    assert_equal GAME.fetch("away"), match.reload.away_units_position, "the home frame, as the legacy app stored it"
    assert_raises(Match::Refused) { match.set_up!(@away, away_lineup) }
  end

  test "the second army starts the game: the first mover is chosen and mailed" do
    match = Match.challenge!(@home, "brienne")
    match.accept!(@away)
    match.set_up!(@away, away_lineup)
    Studio::EmailDelivery.delete_all
    match.set_up!(@home, home_lineup)
    match.reload

    assert_equal Match::IN_PROGRESS, match.match_status
    assert_equal 1, match.turn
    assert_equal GAME.fetch("first"), match.who_started
    assert_equal GAME.fetch("first"), match.whos_turn
    assert_equal [ [ "MatchMailer#your_turn", "arya@example.com" ] ], mail_keys, "home moves first in this game"
  end

  # ---- Turns ----

  test "a turn is refused out of turn, from a stranger, or against the rules, and nothing changes" do
    match = started_match(@home, @away)
    first = GAME.fetch("turns").first
    before = match.reload.attributes

    assert_raises(Match::Refused) { match.play!(@away, steps_for(first)) }
    home_move_from_away_seat = first.fetch("steps").map { |step| step.map { mirror(_1) } }
    error = assert_raises(Match::Refused, "the away player may not move the home army on home's turn") do
      match.play!(@away, home_move_from_away_seat)
    end
    assert_match "turn", error.message
    assert_raises(Match::Refused) { match.play!(make_player("cersei"), steps_for(first)) }
    from = first.fetch("steps").first.first
    assert_raises(Match::Refused) { match.play!(@home, [ [ from, from ] ]) }
    assert_raises(Match::Refused) { match.play!(@home, [ [ from, "x" ] ]) }
    assert_raises(Match::Refused) { match.play!(@home, nil) }
    assert_equal before, match.reload.attributes
  end

  test "a legal turn is saved in the legacy columns and the other player is mailed" do
    match = started_match(@home, @away)
    Studio::EmailDelivery.delete_all
    first = GAME.fetch("turns").first
    match.play!(@home, steps_for(first))
    match.reload

    assert_equal first.fetch("turn"), match.turn
    assert_equal Match::AWAY, match.whos_turn
    assert_equal first.fetch("lastMove").join(","), match.last_move
    assert_equal [ [ "MatchMailer#your_turn", "brienne@example.com" ] ], mail_keys
  end

  test "the away player moves from their own seat, turned into the home frame" do
    match = started_match(@home, @away)
    turns = GAME.fetch("turns")
    match.play!(@home, steps_for(turns[0]))
    match.play!(@away, steps_for(turns[1]))

    assert_equal turns[1].fetch("lastMove").join(","), match.reload.last_move
  end

  test "the recorded game played to the end: the king falls, the record counts it, no more mail" do
    match = started_match(@home, @away)
    GAME.fetch("turns").each do |turn|
      mover = turn.fetch("mover") == Match::HOME ? @home : @away
      Studio::EmailDelivery.delete_all
      match.play!(mover, steps_for(turn))
    end
    match.reload

    assert_equal Match::FINISHED, match.match_status
    assert_equal "king", match.finish_reason
    assert_equal @away, match.winner, "the away side wins this recorded game"
    assert_equal [ 0, 1 ], [ @home.reload.wins, @home.losses ]
    assert_equal [ 1, 0 ], [ @away.reload.wins, @away.losses ]
    assert_empty mail_keys, "the finishing move asks nobody to move"
    assert_raises(Match::Refused) { match.play!(@home, [ [ 52, 53 ] ]) }
  end

  test "resigning hands the opponent the win" do
    match = started_match(@home, @away)
    match.resign!(@away)

    assert_equal [ Match::FINISHED, "resigned", @home ], [ match.reload.match_status, match.finish_reason, match.winner ]
    assert_equal 1, @home.reload.wins
    assert_equal 1, @away.reload.losses
    assert_raises(Match::Refused) { match.resign!(@home) }
  end

  # ---- The seven-day clock ----

  test "a player gets seven days to move; one second more and they forfeit" do
    match = started_match(@home, @away)
    moved_at = match.reload.time_of_last_move
    assert_equal moved_at + 7.days, match.deadline

    Match.expire_stale!(now: moved_at + 7.days - 1.second)
    assert match.reload.in_progress?

    Match.expire_stale!(now: moved_at + 7.days + 1.second)
    match.reload
    assert_equal [ Match::FINISHED, "forfeit" ], [ match.match_status, match.finish_reason ]
    assert_equal @away, match.winner, "home was to move and let the clock run out"
    assert_equal 1, @home.reload.losses
    assert_equal 1, @away.reload.wins
  end

  test "a move after the clock ran out is refused and the match is forfeited" do
    match = started_match(@home, @away)
    travel 8.days do
      error = assert_raises(Match::Refused) { match.play!(@home, steps_for(GAME.fetch("turns").first)) }
      assert_match "seven-day clock", error.message
    end
    assert_equal "forfeit", match.reload.finish_reason
  end

  test "a challenge nobody plays expires after seven days with no result" do
    match = Match.challenge!(@home, "brienne")
    Match.expire_stale!(now: 8.days.from_now)
    match.reload

    assert_equal [ Match::FINISHED, "expired", nil ], [ match.match_status, match.finish_reason, match.winner ]
    assert_equal [ 0, 0, 0, 0 ], [ @home.reload.wins, @home.losses, @away.reload.wins, @away.losses ]
  end

  test "the sweep leaves finished matches and fresh ones alone" do
    fresh = started_match(@home, @away)
    done = started_match(@away, make_player("cersei"))
    done.resign!(@away)

    assert_no_changes -> { [ fresh.reload.updated_at, done.reload.updated_at ] } do
      Match.expire_stale!(now: 1.day.from_now)
    end
  end

  # ---- What each player sees ----

  test "before play each player sees only their own army" do
    match = Match.challenge!(@home, "brienne")
    match.accept!(@away)
    match.set_up!(@home, home_lineup)
    state = match.reload.state_for(@away)

    assert_equal "setup", state[:phase]
    assert_empty state[:units], "the challenger's setup is secret"
    assert state[:can_set_up]
    assert state[:opponent][:ready]
    assert_equal 19, match.state_for(@home)[:units].size
  end

  test "in play both armies show, each from its own seat" do
    match = started_match(@home, @away)
    home_view = match.state_for(@home)
    away_view = match.state_for(@away)

    assert_equal 38, home_view[:units].size
    mine = ->(state) { state[:units].select { |team, *| team == 1 }.map { |_, _, hex, _| hex } }
    assert(mine.(home_view).all? { (52..91).cover?(_1) })
    assert(mine.(away_view).all? { (52..91).cover?(_1) }, "the away player sees their army at the bottom too")
    assert_equal [ true, 1 ], [ home_view[:your_turn], home_view[:offense] ]
    assert_equal [ false, 0 ], [ away_view[:your_turn], away_view[:offense] ]
  end
end
