require "test_helper"

# [unit] The live leaderboard's rule (Leaderboard): wins in live matches, from
# a human seat no computer took over; computers and guests never on it; wins
# over computers count; ranked by wins, then fewest losses, then the latest
# win. And the all-time board from the won/lost record.
class LeaderboardTest < ActiveSupport::TestCase
  include LiveResults

  setup do
    @arya = player("arya")
    @brienne = player("brienne")
    @qavo = computer
  end

  def live_names = Leaderboard.live.map { |row| row.user.username }

  test "an empty board has no rows" do
    assert_empty Leaderboard.live
  end

  test "a win over a computer player counts" do
    live_result(@arya, @qavo, winner: @arya)

    row = Leaderboard.live.sole
    assert_equal [ 1, "arya", 1, 0 ], [ row.rank, row.user.username, row.wins, row.losses ]
  end

  test "a computer player's win never counts, and a computer never appears" do
    live_result(@arya, @qavo, winner: @qavo)
    live_result(@brienne, @qavo, winner: @qavo)

    assert_empty Leaderboard.live
  end

  test "a computer never appears even if its seat is not marked a bot" do
    live_result(@qavo, @arya, winner: @qavo, away_bot: false)

    assert_empty Leaderboard.live
  end

  test "a stand-in's win counts for nobody, not even the player whose seat it took" do
    live_result(@arya, @brienne, winner: @arya, home_bot: true, home_strikes: 2)

    assert_empty Leaderboard.live
  end

  test "beating a player whose seat was taken over counts for the winner" do
    live_result(@arya, @brienne, winner: @brienne, home_bot: true, home_strikes: 2)

    row = Leaderboard.live.sole
    assert_equal [ "brienne", 1, 0 ], [ row.user.username, row.wins, row.losses ]
  end

  test "a loss in a seat a computer took over is nobody's loss" do
    live_result(@arya, @brienne, winner: @arya)
    live_result(@arya, @brienne, winner: @brienne, home_bot: true, home_strikes: 2)

    row = Leaderboard.live.find { |r| r.user == @arya }
    assert_equal [ 1, 0 ], [ row.wins, row.losses ]
  end

  test "guests never appear, even with wins" do
    guest = User.create_guest!(rng: Random.new(3))
    live_result(guest, @qavo, winner: guest)
    live_result(guest, @arya, winner: guest)

    assert_empty Leaderboard.live, "arya lost and has no win; the guest is not shown"
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

  test "a player with losses and no win is not on the board" do
    live_result(@arya, @brienne, winner: @brienne)

    assert_equal [ "brienne" ], live_names
  end

  test "ranked by wins, then fewest losses, then the most recent win" do
    cersei = player("cersei")
    davos = player("davos")
    # arya: 3 wins. brienne and cersei: 2 wins, cersei with more losses.
    # davos: 2 wins, 0 losses like brienne, but his latest win is newer.
    3.times { live_result(@arya, @qavo, winner: @arya, finished_at: 3.hours.ago) }
    2.times { live_result(@brienne, @qavo, winner: @brienne, finished_at: 2.hours.ago) }
    2.times { live_result(davos, @qavo, winner: davos, finished_at: 1.hour.ago) }
    2.times { live_result(cersei, @qavo, winner: cersei, finished_at: 1.minute.ago) }
    live_result(cersei, @qavo, winner: @qavo)

    rows = Leaderboard.live
    assert_equal %w[arya davos brienne cersei], rows.map { |r| r.user.username }
    assert_equal [ 1, 2, 3, 4 ], rows.map(&:rank)
    assert_equal [ 3, 2, 2, 2 ], rows.map(&:wins)
    assert_equal [ 0, 0, 0, 1 ], rows.map(&:losses)
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
