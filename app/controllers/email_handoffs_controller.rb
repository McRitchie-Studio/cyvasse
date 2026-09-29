# GET /auth/email_handoff?assertion=<JWT>&return_to=<path> — the hub's email
# CTA signs a player in (the contract is in EmailHandoff).
#
#   a good assertion, an account   signed in (GuestClaim runs, as on every
#                                  sign-in), the session marked email_handoff,
#                                  then onboarding if the account is
#                                  incomplete, else return_to or Play Now
#   a good assertion, no account   Play Now, signed out; no account is made
#   anything else                  Play Now, and the session is not touched
#
# Every answer is a redirect, which drops the assertion from the address bar;
# `assertion` is a filtered parameter, so no log line carries it. The email's
# ref, from the assertion, is kept for EmailReferral's beacons.
class EmailHandoffsController < ApplicationController
  skip_before_action :require_authentication

  # The rate limiter counts in Rails.cache (the file store, per dyno, in
  # production). The test environment's cache is the null store, which never
  # counts, so tests get a store of their own.
  RATE_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  RATE = 10
  RATE_WINDOW = 1.minute

  rate_limit to: RATE, within: RATE_WINDOW, store: RATE_STORE, with: :too_many_attempts

  def show
    result = EmailHandoff::Verifier.new.call(params[:assertion])
    return rejected(result.reason) unless result.ok?

    store_email_ref(result.ref)
    user = User.where(guest: false).find_by(email: result.email)
    return no_account unless user

    signed_in(user)
  end

  private

  def signed_in(user)
    record_attempt("signed_in", user:)
    # A player already signed in to this account the normal way keeps that
    # session; a handoff never weakens it.
    unless current_user == user && !email_handoff_session?
      set_app_session(user)
      session[EmailHandoff::SESSION_KEY] = EmailHandoff::SESSION_VALUE
    end

    back = local_path(params[:return_to])
    if user.onboarding_due?
      session[OnboardingPrompt::RETURN_TO] = back
      redirect_to onboarding_path
    else
      redirect_to back || root_path
    end
  end

  def no_account
    record_attempt("no_account")
    redirect_to root_path, notice: "Play now, or sign in with this email to save your games."
  end

  def rejected(reason)
    log_rejection(reason)
    redirect_to root_path, alert: "That sign-in link has expired. Sign in to keep playing."
  end

  def too_many_attempts
    log_rejection(:rate_limited)
    render plain: "Too many sign-in attempts. Try again in a minute.", status: :too_many_requests
  end

  def log_rejection(reason)
    if reason == :not_configured
      # Named, and in ErrorLog: every email CTA is failing until the key is set.
      begin
        create_error_log(EmailHandoff::NotConfigured.new("#{EmailHandoff::KEY_ENV} is missing or unreadable"))
      rescue StandardError
        nil
      end
    end
    Rails.logger.warn("[email_handoff] rejected reason=#{reason}")
    record_attempt("rejected", reason:)
  end

  def record_attempt(outcome, reason: nil, user: nil)
    rescue_and_log(target: user) { EmailHandoffAttempt.record(outcome, reason:, user:) }
  rescue StandardError
    nil # logged above; the audit row never decides a sign-in
  end
end
