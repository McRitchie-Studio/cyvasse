# Choose or change the public username other players challenge you by, from
# its own page (/username) or from the profile's Username card
# (profiles/_username, task cyvasse-profile-username-edit). The rules are the
# model's (User::USERNAME_FORMAT, username_free_in_any_case,
# username_not_reserved), the same ones onboarding saves through.
#
# Not a sensitive action (ConfirmedSession): the username is the public name,
# not a way to sign in, and onboarding already lets an email-handoff session
# set it, so such a session may change it here too.
class UsernamesController < ApplicationController
  include RequiresUsername

  # Changes per player, so nobody can churn through names to pass as someone
  # who just left one. Failed attempts count too. The test environment's cache
  # is the null store, which never counts, so tests get a store of their own.
  RATE = 10
  RATE_WINDOW = 1.hour
  RATE_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  TOO_OFTEN = "You have changed your username too often. Try again in an hour.".freeze

  rate_limit to: RATE, within: RATE_WINDOW, store: RATE_STORE, only: :update,
             by: -> { current_user.id }, with: :too_often

  def edit
    @return_to = safe_return_path(params[:return_to], matches_path)
  end

  def update
    @return_to = safe_return_path(params[:return_to], matches_path)
    saved = rescue_and_log(target: current_user) { current_user.update(username: params[:username].to_s.strip) }
    if saved
      redirect_to @return_to, notice: "You play as #{current_user.player_name}.", status: :see_other
    elsif from_profile?
      back_to_profile("Username #{current_user.errors[:username].to_sentence}.", attempt: params[:username].to_s.strip)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # The profile's card posts here; a refusal goes back to it, with the name
  # tried and why shown in the card, rather than to the bare /username page.
  def from_profile?
    params[:from] == "profile"
  end

  def back_to_profile(error, attempt: nil)
    flash[:username_error] = error
    flash[:username_attempt] = attempt.first(40) if attempt
    redirect_to edit_profile_path(anchor: "username"), status: :see_other
  end

  def too_often
    return back_to_profile(TOO_OFTEN, attempt: params[:username].to_s.strip) if from_profile?

    redirect_to username_path(return_to: safe_return_path(params[:return_to], matches_path)),
                alert: TOO_OFTEN, status: :see_other
  end
end
