class ApplicationController < ActionController::Base
  # Preview fetchers (iMessage, Slack, Discord, X...) get a slim page under
  # Apple's 1 MiB limit: the page's own head tags and a one-card body
  # (studio-engine docs/LINK_PREVIEW.md; test/integration/link_preview_test.rb).
  include Studio::LinkPreviewBots

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
  # Never a link-preview fetcher: iMessage's names itself Safari 9.0.1, which
  # :modern answers with a 406, and no link to Cyvasse would unfurl in Messages
  # (task cyvasse-adopts-link-preview; test/integration/link_preview_test.rb).
  allow_browser versions: :modern, unless: :link_preview_bot_request?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # The first page after a sign-in opens the onboarding when the account is
  # incomplete.
  include OnboardingPrompt

  # A session an email handoff started needs a fresh magic link before it
  # changes the email or a sign-in method.
  include ConfirmedSession

  # Back from the game-over modal's sign-in in a browser that never played as
  # the guest (the email link opened on another device): nothing was claimed,
  # so say where the guest's games are. After the onboarding, which may come
  # first.
  before_action :note_guest_left_behind, if: -> { params[:from_guest].present? }
  LEFT_BEHIND = :guest_left_behind_until
  LEFT_BEHIND_WINDOW = 10.minutes

  private

  # Every sign-in passes through here: the engine's magic link, hub SSO, local
  # review, the email handoff, and Play Now's guest (LiveSeeksController). A
  # Play Now guest is bound to this browser's session (GuestClaim.bind), so
  # signing in to a real account in the same browser afterwards (even after
  # signing out of the guest) claims the guest's games. Only the session
  # names the guest: a sign-in in another browser claims nothing.
  def set_app_session(user)
    guest = signed_in_guest
    super
    @current_user = user
    # A fresh sign-in is a normal one; EmailHandoffsController marks its own.
    session.delete(EmailHandoff::SESSION_KEY)
    session.delete(LEFT_BEHIND)
    prompt_onboarding(user)
    if user.guest?
      GuestClaim.bind(session, user)
    else
      if guest
        claim_guest(guest, user)
      else
        session[LEFT_BEHIND] = LEFT_BEHIND_WINDOW.from_now.to_i
      end
      remember_google_return
    end
  end

  # Google's callback always lands on the home page; the sign-in modal names
  # the page to come back to in the request (?return_to=, which OmniAuth keeps
  # in omniauth.params), and PagesController#index sends the player there once.
  AFTER_SIGN_IN = :after_sign_in_path

  def remember_google_return
    path = request.env["omniauth.params"]&.dig("return_to").to_s
    session[AFTER_SIGN_IN] = path if path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
  end

  # `path` when it is a path on this site, else nil: never "//host", a scheme,
  # or a backslash some browsers read as a slash.
  def local_path(path)
    path = path.to_s
    path if path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
  end

  def signed_in_guest
    return current_user if current_user&.guest?

    GuestClaim.bound_guest(session)
  end

  def claim_guest(guest, user)
    rescue_and_log(target: user, parent: guest) { GuestClaim.call(guest:, user:) }
    GuestClaim.release(session)
  rescue StandardError
    # Logged above. The sign-in itself stands, and the guest id stays in the
    # session, so the next sign-in tries the claim again.
    nil
  end

  def note_guest_left_behind
    window = session.delete(LEFT_BEHIND).to_i
    return unless current_user && !current_user.guest? && Time.current.to_i < window

    flash.now[:notice] = "Your guest games stay in the browser you played in. Sign in there to keep them."
  end
end
