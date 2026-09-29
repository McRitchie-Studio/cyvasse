require "test_helper"

# [unit] A guest signs in (GuestClaim): their match seats, wins, searches and
# messages move to the account, their record is added to it, and the guest is
# deleted, or kept retired when a match against the account itself pins it.
class GuestClaimTest < ActiveSupport::TestCase
  include LiveResults

  setup do
    @guest = User.create_guest!(rng: Random.new(11))
    @arya = player("arya")
    @brienne = player("brienne")
    @qavo = computer
  end

  test "the guest's live matches, wins, searches and messages move to the account" do
    won = live_result(@guest, @qavo, winner: @guest)
    lost = live_result(@brienne, @guest, winner: @brienne)
    seek = LiveSeek.create!(user: @guest, last_seen_at: Time.current, match: won)
    message = Message.create!(sender: @guest, receiver: @brienne, match: lost, message: "gg")
    @guest.update_columns(wins: 1, losses: 1)
    @arya.update_columns(wins: 5, losses: 2)

    assert GuestClaim.call(guest: @guest, user: @arya)

    assert_equal [ @arya, @arya ], [ won.reload.home_user, won.winner ]
    assert_equal [ @brienne, @arya ], [ lost.reload.home_user, lost.away_user ]
    assert_equal @brienne, lost.winner
    assert_equal @arya, seek.reload.user
    assert_equal @arya, message.reload.sender
    assert_equal [ 6, 3 ], [ @arya.reload.wins, @arya.losses ]
    assert_nil User.find_by(id: @guest.id), "the guest is deleted"
    board = Leaderboard.live.to_h { |r| [ r.user.username, [ r.points, r.wins, r.losses ] ] }
    assert_equal({ "brienne" => [ 3, 1, 0 ], "arya" => [ 4, 1, 1 ] }, board, "the guest's win and loss are arya's now")
  end

  test "a match between the guest and the account stays, and the guest is kept retired" do
    own = live_result(@guest, @arya, winner: @guest)
    moved = live_result(@guest, @qavo, winner: @guest)
    @guest.update_columns(wins: 2)

    assert GuestClaim.call(guest: @guest, user: @arya)

    assert_equal [ @guest, @guest ], [ own.reload.home_user, own.winner ]
    assert_equal @arya, moved.reload.home_user
    assert @guest.reload.guest?
    assert_equal [ 0, 0 ], [ @guest.wins, @guest.losses ], "the record moved; it is not counted twice"
    assert_equal 2, @arya.reload.wins
  end

  test "only a guest is claimed, and only by a real account" do
    live_result(@brienne, @qavo, winner: @brienne)

    assert_not GuestClaim.call(guest: @brienne, user: @arya), "an account is never claimed"
    assert_not GuestClaim.call(guest: @guest, user: User.create_guest!(rng: Random.new(12))), "a guest claims nothing"
    assert_not GuestClaim.call(guest: @guest, user: @qavo), "a computer claims nothing"
    assert_not GuestClaim.call(guest: @guest, user: @guest)
    assert_not GuestClaim.call(guest: nil, user: @arya)
    assert User.exists?(@guest.id)
  end

  test "claiming twice is harmless" do
    live_result(@guest, @qavo, winner: @guest)
    assert GuestClaim.call(guest: @guest, user: @arya)
    assert_not GuestClaim.call(guest: @guest, user: @brienne)
    assert_equal 1, Match.involving(@arya).count
  end

  test "a brand-new account takes the guest's games, lineups and piece art whole" do
    newcomer = User.create!(email: "newcomer@example.com")
    won = live_result(@guest, @qavo, winner: @guest)
    lineup = Setup.create!(user: @guest, button_position: 2, name: "Wall", units_position: army)
    @guest.update_columns(wins: 1, piece_skin: "pencil")

    assert GuestClaim.call(guest: @guest, user: newcomer)

    assert_equal newcomer, won.reload.winner
    assert_equal newcomer, lineup.reload.user
    assert_equal [ 1, 0, "pencil" ], [ newcomer.reload.wins, newcomer.losses, newcomer.piece_skin ]
  end

  test "an account with games of its own keeps them, its lineups and its art" do
    own = live_result(@arya, @qavo, winner: @arya)
    guests = live_result(@guest, @qavo, winner: @qavo)
    kept = Setup.create!(user: @arya, button_position: 1, name: "Mine", units_position: army)
    clash = Setup.create!(user: @guest, button_position: 1, name: "Theirs", units_position: army)
    free = Setup.create!(user: @guest, button_position: 3, name: "Spare", units_position: army)
    @arya.update_columns(wins: 4, losses: 1, piece_skin: "vector")
    @guest.update_columns(losses: 1, piece_skin: "pencil")

    assert GuestClaim.call(guest: @guest, user: @arya)

    assert_equal [ @arya, @arya ], [ own.reload.home_user, guests.reload.home_user ]
    assert_equal [ 4, 2, "vector" ], [ @arya.reload.wins, @arya.losses, @arya.piece_skin ]
    assert_equal({ 1 => "Mine", 2 => nil, 3 => "Spare" }, Setup.slots_for(@arya).transform_values { _1&.name })
    assert_equal @arya, kept.reload.user
    assert_not Setup.exists?(clash.id), "a slot the account holds is not overwritten"
    assert_equal @arya, free.reload.user
    board = Leaderboard.live.to_h { |r| [ r.user.username, [ r.wins, r.losses ] ] }
    assert_equal [ 1, 1 ], board["arya"], "the live board recounts from the moved matches"
  end

  test "a guest with no games is simply retired" do
    assert GuestClaim.call(guest: @guest, user: @arya)
    assert_nil User.find_by(id: @guest.id)
    assert_equal [ 0, 0 ], [ @arya.reload.wins, @arya.losses ]
  end

  test "a guest kept for a match against the account is marked merged and never claimed again" do
    live_result(@guest, @arya, winner: @guest)
    assert GuestClaim.call(guest: @guest, user: @arya)
    assert_equal @arya, @guest.reload.merged_into

    live_result(@guest, @qavo, winner: @guest)
    @guest.update_columns(wins: 1)
    assert_not GuestClaim.call(guest: @guest, user: @arya), "the same sign-in twice changes nothing"
    assert_not GuestClaim.call(guest: @guest, user: @brienne), "nor may another account take it"
    assert_equal 0, @brienne.reload.wins
    assert_nil GuestClaim.guest_from_token(GuestClaim.token_for(@guest)), "its old claim token is spent"
  end

  test "a failure moves nothing" do
    won = live_result(@guest, @qavo, winner: @guest)
    @guest.update_columns(wins: 1)
    claim = GuestClaim.new(guest: @guest, user: @arya)
    claim.define_singleton_method(:retire) { |_guest| raise ActiveRecord::StatementInvalid, "boom" }

    assert_raises(ActiveRecord::StatementInvalid) { claim.call }
    assert_equal @guest, won.reload.winner
    assert_equal 0, @arya.reload.wins
  end

  test "a claim token names its guest; a forged, expired or spent one names nobody" do
    token = GuestClaim.token_for(@guest)

    assert_equal @guest, GuestClaim.guest_from_token(token)
    assert_nil GuestClaim.guest_from_token("#{token}x")
    assert_nil GuestClaim.guest_from_token("")
    assert_nil GuestClaim.guest_from_token(Rails.application.message_verifier(:other).generate(@guest.id))
    travel(GuestClaim::TOKEN_LIFE + 1.minute) { assert_nil GuestClaim.guest_from_token(token) }
    GuestClaim.call(guest: @guest, user: @arya)
    assert_nil GuestClaim.guest_from_token(token)
  end

  private

  # A whole army on the owner's rows (Setup validates one on create).
  def army
    CyvasseRules::Bot.lineup(rng: Random.new(3))
  end
end
