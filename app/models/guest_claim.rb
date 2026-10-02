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
# Only the guest this browser played as is ever claimed, and the binding is
# the browser's own session (Rails' encrypted cookie, which no one can read,
# forge or be sent): Play Now writes the guest's id there (GuestClaim.bind)
# and a sign-in in that same browser reads it back (GuestClaim.bound_guest).
# Nothing in a request or a URL can name a guest: a sign-in link opened in
# another browser or on another device claims nothing, so a guest who asks
# for a link to someone else's email can never push its games and chat onto
# that account (task cyvasse-guest-claim-hardening). The guest stays bound to
# the browser it played in, and a sign-in there later still claims it.
#
# Called on every sign-in (ApplicationController#set_app_session).
class GuestClaim
  # Under this key since the first claim, so sessions already out there keep it.
  SESSION_KEY = :guest_user_id

  # Binds a Play Now guest to this browser's session.
  def self.bind(session, guest)
    session[SESSION_KEY] = guest.id
  end

  # The guest this session was bound to, while it may still be claimed; nil
  # for a session that never played as one.
  def self.bound_guest(session)
    id = session[SESSION_KEY]
    id && User.claimable_guests.find_by(id:)
  end

  # After a claim: the session holds no guest any more.
  def self.release(session)
    session.delete(SESSION_KEY)
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
