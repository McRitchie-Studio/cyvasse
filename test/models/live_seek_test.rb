require "test_helper"

# [unit] Play Now matchmaking (LiveSeek): two live searchers are paired, a
# search nobody answers ends against a computer player, and a searcher who
# stopped asking is never paired.
class LiveSeekTest < ActiveSupport::TestCase
  include MatchPlay
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
  end

  test "a second searcher is paired with the first, who takes the home seat" do
    first = LiveSeek.join!(@arya)
    assert_nil first.match

    second = LiveSeek.join!(@brienne)
    match = second.match
    assert match.live?
    assert_equal [ @arya, @brienne ], [ match.home_user, match.away_user ]
    assert_equal match, first.reload.match
  end

  test "nobody found in the search time plays a computer player" do
    seek = LiveSeek.join!(@arya)
    travel 19.seconds do
      assert_nil seek.settle!.match
    end
    travel 21.seconds do
      match = seek.settle!.match
      assert match.away_user.computer?
      assert match.away_ready?, "the computer is set up already"
    end
  end

  test "a searcher who stopped asking is not paired" do
    LiveSeek.join!(@arya)
    travel 6.seconds do
      assert_nil LiveSeek.join!(@brienne).match
    end
  end

  test "a searcher still asking is paired even late in their search" do
    first = LiveSeek.join!(@arya)
    travel 15.seconds do
      first.settle!
      paired = LiveSeek.join!(@brienne).match
      assert paired
      assert_equal paired, first.reload.match
    end
  end

  test "pressing Play Now again replaces your open search" do
    LiveSeek.join!(@arya)
    LiveSeek.join!(@arya)
    assert_equal 1, LiveSeek.open.where(user: @arya).count
  end

  test "a guest gets a temporary name and no email" do
    guest = User.create_guest!(rng: Random.new(1))
    assert guest.guest?
    assert_match(/\AGuest_\d{4}\z/, guest.username)
    assert_nil guest.email
  end
end
