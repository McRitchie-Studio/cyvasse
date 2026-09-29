# A session an email handoff started (EmailHandoff) may play, chat and finish
# onboarding. Changing the email, a sign-in method, or deleting the account
# needs more: a fresh magic link sent to the address, whose click confirms the
# session (SessionConfirmationsController).
#
# The guarded actions, by controller:
#   studio/profiles#update         when it changes the email
#   studio/profiles#unlink_google  removes a sign-in method
#   omniauth_callbacks#create      Google sign-in links Google to the account
#
# An account deletion route, when one is added, belongs in SENSITIVE too.
module ConfirmedSession
  extend ActiveSupport::Concern

  SENSITIVE = {
    "studio/profiles" => %w[unlink_google],
    "omniauth_callbacks" => %w[create]
  }.freeze
  PURPOSE = :session_confirmation
  LINK_LIFE = 30.minutes
  # One confirmation email per session in this window.
  RESEND_AFTER = 2.minutes

  included do
    before_action :require_confirmed_session, if: :sensitive_action?
    helper_method :email_handoff_session?
  end

  # The signed return address inside the confirmation email. Only the email
  # carries it, so reaching it proves the click.
  def self.token_for(user)
    Rails.application.message_verifier(PURPOSE).generate(user.id, expires_in: LINK_LIFE)
  end

  def self.user_id_from(token)
    Rails.application.message_verifier(PURPOSE).verified(token.to_s)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  private

  def email_handoff_session?
    logged_in? && session[EmailHandoff::SESSION_KEY] == EmailHandoff::SESSION_VALUE
  end

  def sensitive_action?
    return false unless email_handoff_session?

    SENSITIVE.fetch(controller_path, []).include?(action_name) || email_change_request?
  end

  def email_change_request?
    return false unless controller_path == "studio/profiles" && action_name == "update"

    email = params.dig(:profile, :email).to_s.strip
    email.present? && !email.casecmp?(current_user.email.to_s)
  end

  def require_confirmed_session
    send_session_confirmation
    respond_to do |format|
      format.html do
        redirect_to root_path, status: :see_other,
                               alert: "To change how you sign in, confirm it's you: we emailed a link to #{current_user.email}."
      end
      format.any { head :forbidden }
    end
  end

  # Emails a normal magic link that comes back to the confirmation page.
  def send_session_confirmation(return_to: nil)
    sent = session[:session_confirmation_sent_at].to_i
    return if Time.current.to_i - sent < RESEND_AFTER

    user = current_user
    back = confirm_session_path(t: ConfirmedSession.token_for(user), return_to: return_to.presence)
    link = Studio::Link.create_magic_link(email: user.email, return_to: back, ttl: LINK_LIFE)
    Studio::Email.deliver(UserMailer, :magic_link, user.email, link.token, to: user.email, user:)
    session[:session_confirmation_sent_at] = Time.current.to_i
  end
end
