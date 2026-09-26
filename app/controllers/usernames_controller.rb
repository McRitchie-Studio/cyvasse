# Choose or change the public username other players challenge you by.
class UsernamesController < ApplicationController
  include RequiresUsername

  def edit
    @return_to = safe_return_path(params[:return_to], matches_path)
  end

  def update
    @return_to = safe_return_path(params[:return_to], matches_path)
    saved = rescue_and_log(target: current_user) { current_user.update(username: params[:username].to_s.strip) }
    if saved
      redirect_to @return_to, notice: "You play as #{current_user.username}.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
