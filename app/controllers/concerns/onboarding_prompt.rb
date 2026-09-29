# Opens the onboarding (OnboardingController) once after a sign-in, when the
# account is incomplete (User#onboarding_due?). Every sign-in passes through
# ApplicationController#set_app_session, which calls prompt_onboarding; the
# first full page after it is swapped for the flow, which then returns the
# player to that page. The flow is never forced twice in one sign-in.
module OnboardingPrompt
  extend ActiveSupport::Concern

  PENDING = :onboarding_pending
  RETURN_TO = :onboarding_return_to

  # Sign-ins that never open it: a desk's local review, which must land the
  # reviewer on the page under review.
  QUIET_SIGN_INS = %w[studio/local_reviews].freeze

  # Pages it never interrupts: the flow itself and the sign-in doors.
  EXEMPT = %w[onboarding email_handoffs session_confirmations sessions studio/links magic_links
              omniauth_callbacks studio/local_reviews studio/local_emails].freeze

  included do
    before_action :open_onboarding, if: -> { session[PENDING] }
  end

  private

  def prompt_onboarding(user)
    session[PENDING] = true unless user.guest? || QUIET_SIGN_INS.include?(controller_path)
  end

  def open_onboarding
    return unless request.get? && full_page_request? && EXEMPT.exclude?(controller_path)

    session.delete(PENDING)
    return unless current_user&.onboarding_due?

    session[RETURN_TO] = request.fullpath
    redirect_to onboarding_path
  end
end
