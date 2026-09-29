class ApplicationController < ActionController::Base
  # Passwordless auth, hub SSO awareness, and rescue_and_log / ErrorLog.
  # NOTE: this adds `before_action :require_authentication` to every
  # controller. PagesController and GamesController opt out
  # (test/integration/auth_gate_test.rb pins both sides).
  include Studio::ErrorHandling

  # current_skin: which piece art (pencil or vector) this player sees.
  include PieceSkinPreference

  # email_ref: credits sign-ins and games to the email that brought a player.
  include EmailReferral

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # A guest who signed in from another browser claims their games through the
  # signed token in the sign-in email's return address (GuestClaim).
  # Only on the first request after a sign-in, within this window.
  before_action :claim_guest_from_link, if: -> { params[:claim].present? }
  CLAIM_WINDOW = 2.minutes

  private

  # Every sign-in passes through here: the engine's magic link, hub SSO, local
  # review, and Play Now's guest (LiveSeeksController). A Play Now guest's id is
  # kept in the session under its own key, so that signing in to a real account
  # afterwards (even after signing out of the guest) claims the guest's games.
  def set_app_session(user)
    guest = signed_in_guest
    super
    @current_user = user
    if user.guest?
      session[:guest_user_id] = user.id
    else
      claim_guest(guest, user) if guest
      # Only the redirect right after this sign-in may claim by link: a
      # claim link opened later (sent by a guest to a signed-in player) must
      # not push the guest's games and chat onto that player.
      session[:claim_window_until] = CLAIM_WINDOW.from_now.to_i
    end
  end

  def signed_in_guest
    return current_user if current_user&.guest?

    User.find_by(id: session[:guest_user_id], guest: true) if session[:guest_user_id]
  end

  def claim_guest(guest, user)
    rescue_and_log(target: user, parent: guest) { GuestClaim.call(guest:, user:) }
    session.delete(:guest_user_id)
  rescue StandardError
    # Logged above. The sign-in itself stands, and the guest id stays in the
    # session, so the next sign-in tries the claim again.
    nil
  end

  def claim_guest_from_link
    window = session.delete(:claim_window_until).to_i
    return unless current_user && !current_user.guest? && Time.current.to_i < window

    guest = GuestClaim.guest_from_token(params[:claim])
    claim_guest(guest, current_user) if guest
  end
end
