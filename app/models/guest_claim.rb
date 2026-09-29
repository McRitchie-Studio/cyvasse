# A Play Now guest signs in (task live-leaderboard-and-guest-claim): their
# games become the account's, so a win played as Guest_4821 goes on the
# leaderboard under the name they sign in with.
#
# Moves every match seat, win, search (LiveSeek) and chat message of the guest
# to the account, its saved lineups into slots the account has free, and its
# piece art if the account chose none; adds the guest's won/lost record to the
# account's, and then deletes the guest. The live leaderboard needs no
# recount: it reads the moved matches. A match the guest played against the
# account itself (two tabs) cannot move, since a player cannot face
# themselves: it stays with the guest, and the guest is kept, marked merged
# (users.merged_into_id) with its record moved away, and is never claimed again.
#
# Only the guest this browser played as is ever passed in: the session's
# guest, or the one a signed token from that session's own page names. A
# guest id from the request is never read.
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
    id && User.claimable_guests.find_by(id:)
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
      guest = User.claimable_guests.lock.find_by(id: @guest.id)
      next false unless guest

      move_matches(guest)
      move_seeks_and_messages(guest)
      move_lineups(guest)
      @user.update_columns(piece_skin: guest.piece_skin) if @user.piece_skin.blank? && guest.piece_skin.present?
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

  # Into the slots the account has free; a slot it holds is never overwritten.
  def move_lineups(guest)
    free = Setup::SLOTS.to_a - Setup.where(user_id: @user.id).distinct.pluck(:button_position)
    Setup.where(user_id: guest.id, button_position: free).update_all(user_id: @user.id)
  end

  # Deleted once nothing points at it; otherwise kept as a guest (never on the
  # board) with its record zeroed, so the moved wins are not counted twice.
  def retire(guest)
    guest.update_columns(wins: 0, losses: 0, merged_into_id: @user.id)
    guest.destroy if guest.home_matches.none? && guest.away_matches.none? &&
                     guest.sent_messages.none? && guest.received_messages.none? && guest.board_posts.none?
  end
end
