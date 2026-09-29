require "test_helper"

# [unit] The live leaderboard's rule (Leaderboard): 1 point per finished live
# game plus 2 more for a win (win 3, loss or draw 1), games against a computer
# included, guests shown; a seat a computer held counts for nobody; ranked by
# points, then wins, then who reached the score first. And the all-time board
# from the won/lost record.
class LeaderboardTest < ActiveSupport::TestCase
  include LiveResults

  setup do
    @arya = player("arya")
    @brienne = player("brienne")
    @qavo = computer
  end

  def live_names = Leaderboard.live.map { |row| row.user.username }
  def line(row) = [ row.rank, row.user.username, row.points, row.wins, row.games ]

  test "an empty board has no rows" do
    assert_empty Leaderboard.live
  end

  test "points: 1 per finished game, 3 for a win" do
    assert_equal 1, Leaderboard.points(games: 1, wins: 0)
    assert_equal 3, Leaderboard.points(games: 1, wins: 1)
    assert_equal 7, Leaderboard.points(games: 3, wins: 2)
  end

  test "a win over a computer player is 3 points" do
    live_result(@arya, @qavo, winner: @arya)

    assert_equal [ 1, "arya", 3, 1, 1 ], line(Leaderboard.live.sole)
  end

  test "a loss to the computer is 1 point and puts the player on the board" do
    live_result(@arya, @qavo, winner: @qavo)

    assert_equal [ 1, "arya", 1, 0, 1 ], line(Leaderboard.live.sole)
  end

  test "a guest who finished a game is on the board under the guest name" do
    guest = User.create_guest!(rng: Random.new(3))
    live_result(guest, @qavo, winner: @qavo)

    assert_equal [ guest.username ], live_names
  end

  test "a guest already merged into an account never appears" do
    guest = User.create_guest!(rng: Random.new(4))
    live_result(guest, @arya, winner: guest)
    guest.update_columns(merged_into_id: @arya.id)

    assert_equal [ "arya" ], live_names
  end

  test "every ending with a result counts: king, resignation, forfeit on the clock, draw" do
    %w[king resigned forfeit].each { |reason| live_result(@arya, @qavo, winner: @arya, finish_reason: reason) }
    live_result(@arya, @brienne, winner: nil, finish_reason: "draw")

    assert_equal [ 1, "arya", 10, 3, 4 ], line(Leaderboard.live.first)
    assert_equal [ 2, "brienne", 1, 0, 1 ], line(Leaderboard.live.second)
  end

  test "a match that expired before play is not a game" do
    live_result(@arya, @qavo, winner: nil, finish_reason: "expired")

    assert_empty Leaderboard.live
  end

  test "a computer player never scores or appears" do
    live_result(@arya, @qavo, winner: @qavo)
    live_result(@qavo, @brienne, winner: @qavo, away_bot: false)

    assert_equal %w[arya brienne], live_names.sort
  end

  test "a seat a computer held after missed clocks counts for nobody, win or loss" do
    live_result(@arya, @brienne, winner: @arya, home_bot: true, home_strikes: 2)
    live_result(@arya, @brienne, winner: @brienne, home_bot: true, home_strikes: 2)

    assert_equal [ [ 1, "brienne", 4, 1, 2 ] ], Leaderboard.live.map { line(_1) }
  end

  test "an account with no username never appears" do
    nameless = User.create!(email: "nameless@example.com", name: "Secret Name")
    live_result(nameless, @qavo, winner: nameless)

    assert_empty Leaderboard.live
  end

  test "only live matches count, and only finished ones" do
    live_result(@arya, @brienne, winner: @arya, live: false)
    Match.start_live!(@brienne, computer: true, rng: Random.new(2))

    assert_empty Leaderboard.live
  end

  test "ranked by points, then more wins, then the earlier to reach the score" do
    cersei = player("cersei")
    davos = player("davos")
    # arya 6 (2 wins). brienne 6 (1 win, 3 losses). cersei and davos 3 (1
    # win); cersei got there first.
    2.times { live_result(@arya, @qavo, winner: @arya, finished_at: 1.minute.ago) }
    live_result(@brienne, @qavo, winner: @brienne, finished_at: 3.hours.ago)
    3.times { live_result(@brienne, @qavo, winner: @qavo, finished_at: 3.hours.ago) }
    live_result(davos, @qavo, winner: davos, finished_at: 1.hour.ago)
    live_result(cersei, @qavo, winner: cersei, finished_at: 2.hours.ago)

    rows = Leaderboard.live
    assert_equal [ [ 1, "arya", 6, 2, 2 ], [ 2, "brienne", 6, 1, 4 ], [ 3, "cersei", 3, 1, 1 ], [ 4, "davos", 3, 1, 1 ] ],
                 rows.map { line(_1) }
    assert_equal 3, rows.second.losses
  end

  test "rank_for gives a player's row wherever they stand, and nil off the board" do
    names = (1..12).map { |i| player("p#{i.to_s.rjust(2, '0')}") }
    names.each_with_index { |p, i| (i + 1).times { live_result(p, @qavo, winner: p) } }

    row = Leaderboard.rank_for(names.first)
    assert_equal [ 12, "p01", 3, 1, 1 ], line(row)
    assert_equal 1, Leaderboard.rank_for(names.last).rank
    assert_nil Leaderboard.rank_for(@arya)
    assert_nil Leaderboard.rank_for(nil)
  end

  test "the live board stops at its limit" do
    names = (1..12).map { |i| player("p#{i.to_s.rjust(2, '0')}") }
    names.each { |p| live_result(p, @qavo, winner: p) }

    assert_equal 10, Leaderboard.live.size
    assert_equal 12, Leaderboard.live(limit: nil).size
  end

  test "the all-time board reads the won/lost record, people only" do
    @arya.update_columns(wins: 40, losses: 9)
    @brienne.update_columns(wins: 40, losses: 3)
    @qavo.update_columns(wins: 900, losses: 5)
    User.create_guest!(rng: Random.new(5)).update_columns(wins: 70)
    player("cersei").update_columns(losses: 4)

    rows = Leaderboard.all_time
    assert_equal %w[brienne arya], rows.map { |r| r.user.username }
    assert_equal [ [ 40, 3 ], [ 40, 9 ] ], rows.map { |r| [ r.wins, r.losses ] }
  end
end
