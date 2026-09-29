# Finishing an incomplete account (User::Onboarding): at most four short
# steps, each saved as it is answered, so leaving part-way loses nothing.
#
#   GET   /onboarding             the first missing step (or ?step=)
#   PATCH /onboarding/:step       save it, then the next missing step
#   POST  /onboarding/:step/skip  pass it over for good (not the username
#                                 when online play cannot use the one held)
#
# "Skip for now" leaves for the page the player was headed to and records
# nothing, so the next sign-in resumes the flow.
class OnboardingController < ApplicationController
  before_action :require_player
  before_action :set_step, only: %i[update skip]

  BIRTH_YEARS = (1900..Date.current.year - 5)

  def show
    session.delete(OnboardingPrompt::PENDING)
    @step = params[:step].presence_in(current_user.onboarding_flow) || current_user.onboarding_missing.first
    return finish unless @step

    current_user.record_onboarding!(@step, "shown")
    load_step
  end

  def update
    if rescue_and_log(target: current_user) { save_step }
      current_user.record_onboarding!(@step, "done")
      advance
    else
      load_step
      render :show, status: :unprocessable_entity
    end
  end

  def skip
    return redirect_to(onboarding_path(step: @step), status: :see_other) if @step == "username" && !current_user.username_playable?

    current_user.record_onboarding!(@step, "skipped")
    advance
  end

  private

  def require_player
    redirect_to root_path if current_user.guest?
  end

  def set_step
    @step = params[:step].presence_in(current_user.onboarding_flow)
    raise ActiveRecord::RecordNotFound, "no onboarding step #{params[:step]}" unless @step
  end

  def advance
    following = current_user.onboarding_flow.drop_while { |step| step != @step }.drop(1)
    step = (current_user.onboarding_missing & following).first
    step ? redirect_to(onboarding_path(step:), status: :see_other) : finish
  end

  def finish
    back = local_path(session.delete(OnboardingPrompt::RETURN_TO)) || root_path
    redirect_to back, status: :see_other, notice: current_user.onboarding_missing.empty? ? "You're all set." : nil
  end

  def load_step
    @return_to = local_path(session[OnboardingPrompt::RETURN_TO]) || root_path
    @position = current_user.onboarding_flow.index(@step) + 1
    @total = current_user.onboarding_flow.size
    case @step
    when "welcome" then @stats = current_user.legacy_stats
    when "username" then @suggestion = current_user.username_playable? ? current_user.username : current_user.suggested_username
    end
  end

  # True when saved; false leaves the errors on current_user for the form.
  def save_step
    case @step
    when "welcome" then true
    when "username" then current_user.update(username: params[:username].to_s.strip)
    when "profile" then save_profile
    when "contact" then current_user.update(email_updates: params[:email_updates] == "1", email_updates_at: Time.current)
    end
  end

  def save_profile
    name = params[:name].to_s.squish
    skin = PieceSkinPreference.normalize(params[:skin])
    birth = birth_date_params
    current_user.errors.add(:name, "can't be blank") if name.blank?
    current_user.errors.add(:name, "is taken by another player") if name.present? && name_taken?(name)
    current_user.errors.add(:birth_date, "is not a real date") if birth == :invalid
    return false if current_user.errors.any?

    current_user.update!(name:, **(birth || {}))
    remember_skin!(skin) if skin
    true
  rescue ActiveRecord::RecordNotUnique
    current_user.errors.add(:name, "is taken by another player")
    false
  end

  # The display name decides the account's unique slug (Sluggable).
  def name_taken?(name)
    User.where(slug: name.parameterize).where.not(id: current_user.id).exists?
  end

  # nil when left blank (it is optional), :invalid when not a real date.
  def birth_date_params
    parts = %i[birth_year birth_month birth_day].map { |key| params[key].presence }
    return nil if parts.all?(&:nil?)

    year, month, day = parts.map { |part| Integer(part, exception: false) }
    return :invalid unless year && month && day && BIRTH_YEARS.cover?(year) && Date.valid_date?(year, month, day)

    { birth_year: year, birth_month: month, birth_day: day }
  end
end
