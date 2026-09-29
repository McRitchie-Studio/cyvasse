# Email handoff sign-ins (EmailHandoffAttempt) and the onboarding funnel
# (User.onboarding_funnel), for admins (task cyvasse-legacy-onboarding-handoff).
module Admin
  class SignInsController < BaseController
    RECENT = 25

    def index
      @summary = EmailHandoffAttempt.summary
      @total = @summary.sum { |row| row[:count] }
      @signed_in = @summary.select { |row| row[:outcome] == "signed_in" }.sum { |row| row[:count] }
      @last_used = @summary.filter_map { |row| row[:last_at] if row[:outcome] == "signed_in" }.max
      @recent = EmailHandoffAttempt.includes(:user).order(created_at: :desc).limit(RECENT)
      @funnel = User.onboarding_funnel
    end
  end
end
