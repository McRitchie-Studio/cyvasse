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

  test "play the computer now starts the timeout's computer match at once" do
    seek = LiveSeek.join!(@arya)
    match = seek.settle!(computer: true).match
    assert match.away_user.computer?
    assert match.away_ready?, "the computer is set up already"
    assert_nil LiveSeek.join!(@brienne).match, "a chosen computer game leaves no open search"
  end

  test "play the computer now keeps a person already found" do
    first = LiveSeek.join!(@arya)
    paired = LiveSeek.join!(@brienne).match
    assert_equal paired, first.settle!(computer: true).match
  end

  test "the setup clock starts after the versus splash, for a person or a computer" do
    freeze_time do
      LiveSeek.join!(@arya)
      paired = LiveSeek.join!(@brienne).match
      computer = LiveSeek.join!(make_player("cersei")).settle!(computer: true).match
      [ paired, computer ].each do |match|
        assert_equal Time.current + LiveSeek::SPLASH + LiveMatch::SETUP_CLOCK, match.live_clock_ends_at
      end
    end
  end

  test "a shortened splash shortens the setup grace with it" do
    Rails.configuration.x.live_splash_time = 2.seconds
    freeze_time do
      match = LiveSeek.join!(@arya).settle!(computer: true).match
      assert_equal Time.current + 2.seconds + LiveMatch::SETUP_CLOCK, match.live_clock_ends_at
    end
  ensure
    Rails.configuration.x.live_splash_time = nil
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

  # A match called off during setup takes both searches with it: they blocked
  # the delete on their foreign key, and an emptied one would read as open.
  test "calling off a paired match before play removes it and both searches" do
    LiveSeek.join!(@arya)
    match = LiveSeek.join!(@brienne).match

    match.withdraw!(@arya)

    assert_not Match.exists?(match.id)
    assert_empty LiveSeek.where(user: [ @arya, @brienne ])
    assert_empty LiveSeek.open, "no search is left to start another match"
  end

  test "a guest gets a temporary name and no email" do
    guest = User.create_guest!(rng: Random.new(1))
    assert guest.guest?
    assert_match(/\AGuest_\d{4}\z/, guest.username)
    assert_nil guest.email
  end
end
