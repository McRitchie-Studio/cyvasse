# A Play Now guest signs in (task live-leaderboard-and-guest-claim): their
# games become the account's, so a win played as Guest_4821 goes on the
# leaderboard under the name they sign in with.
#
# Moves every match seat, win, search (LiveSeek) and chat message of the guest
# to the account, adds the guest's won/lost record to the account's, and then
# deletes the guest. A match the guest played against the account itself (two
# tabs) cannot move, since a player cannot face themselves: it stays with the
# guest, and the guest is kept, retired, with its record moved away.
#
# Called on every sign-in (ApplicationController#set_app_session) and from a
# signed claim token when the email link is opened in another browser
# (ApplicationController#claim_guest_from_link).
class GuestClaim
  PURPOSE = :guest_claim
  TOKEN_LIFE = 1.day

  # A token naming the guest, for the return address in the sign-in email.
  def self.token_for(guest)
    Rails.application.message_verifier(PURPOSE).generate(guest.id, expires_in: TOKEN_LIFE)
  end

  # The guest a token names, or nil for a bad, expired or spent one.
  def self.guest_from_token(token)
    id = Rails.application.message_verifier(PURPOSE).verified(token.to_s)
    id && User.find_by(id:, guest: true)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  # Returns true when the guest's games moved to `user`.
  def self.call(guest:, user:)
    new(guest:, user:).call
  end

  def initialize(guest:, user:)
    @guest = guest
    @user = user
  end

  def call
    return false unless claimable?

    ApplicationRecord.transaction do
      guest = User.lock.find_by(id: @guest.id, guest: true)
      next false unless guest

      move_matches(guest)
      move_seeks_and_messages(guest)
      User.update_counters(@user.id, wins: guest.wins, losses: guest.losses)
      retire(guest)
      true
    end
  end

  private

  def claimable?
    @guest.present? && @user.present? && @guest.guest? && !@user.guest? && !@user.computer? && @guest.id != @user.id
  end

  # Matches between the guest and the account stay where they are.
  def move_matches(guest)
    movable = Match.involving(guest).where.not(home_user_id: @user.id).where.not(away_user_id: @user.id)
    ids = movable.pluck(:id)
    return if ids.empty?

    Match.where(id: ids, home_user_id: guest.id).update_all(home_user_id: @user.id)
    Match.where(id: ids, away_user_id: guest.id).update_all(away_user_id: @user.id)
    Match.where(id: ids, winner_id: guest.id).update_all(winner_id: @user.id)
  end

  def move_seeks_and_messages(guest)
    LiveSeek.where(user_id: guest.id).update_all(user_id: @user.id)
    Message.where(sender_id: guest.id).where.not(receiver_id: @user.id).update_all(sender_id: @user.id)
    Message.where(receiver_id: guest.id).where.not(sender_id: @user.id).update_all(receiver_id: @user.id)
  end

  # Deleted once nothing points at it; otherwise kept as a guest (never on the
  # board) with its record zeroed, so the moved wins are not counted twice.
  def retire(guest)
    guest.update_columns(wins: 0, losses: 0)
    guest.destroy if guest.home_matches.none? && guest.away_matches.none? &&
                     guest.sent_messages.none? && guest.received_messages.none? && guest.board_posts.none?
  end
end
