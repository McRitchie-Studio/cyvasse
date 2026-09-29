# Confirming an email handoff session (ConfirmedSession).
#
#   POST /account/confirmation   emails a fresh magic link to the account
#   GET  /account/confirm?t=     where that link lands once clicked: the
#                                session becomes an ordinary signed-in one
#
# The link is the engine's own magic link (Studio::Link), so clicking it in
# another browser signs that browser in the normal way; clicked in this one,
# the engine leaves the session as it is and this page upgrades it.
class SessionConfirmationsController < ApplicationController
  def create
    send_session_confirmation(return_to: local_path(params[:return_to]))
    redirect_to local_path(params[:return_to]) || root_path, status: :see_other,
                                             notice: "We emailed a link to #{current_user.email}. Open it to confirm it's you."
  end

  def show
    if ConfirmedSession.user_id_from(params[:t]) == current_user.id
      session.delete(EmailHandoff::SESSION_KEY)
      session.delete(:session_confirmation_sent_at)
      redirect_to local_path(params[:return_to]) || root_path, notice: "Confirmed. You can change how you sign in now."
    else
      redirect_to root_path, alert: "That confirmation link has expired. Ask for a new one."
    end
  end
end
