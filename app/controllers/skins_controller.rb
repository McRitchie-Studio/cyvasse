# The piece-skin switcher (epic cyvasse-revival piece 5): PATCH /skin with
# `skin=pencil|vector` remembers the choice and returns the player to the
# page they toggled on.
#
# Public on purpose: a signed-out player's choice lives in a cookie, so the
# switch has nothing to gate. A signed-in player's choice also lands on
# users.piece_skin, which follows them to any browser.
class SkinsController < ApplicationController
  skip_before_action :require_authentication

  def update
    skin = PieceSkinPreference.normalize(params[:skin])
    unless skin
      respond_to do |format|
        format.html { redirect_to return_path, alert: "Unknown piece skin.", status: :see_other }
        format.json { render json: { error: "unknown skin" }, status: :unprocessable_entity }
      end
      return
    end

    rescue_and_log(target: current_user) { remember_skin!(skin) }

    respond_to do |format|
      format.html { redirect_to return_path, status: :see_other }
      format.json { render json: { skin: skin } }
    end
  end

  private

  # Back to the page the toggle sat on. Only a local path is honoured (no
  # "//host" or "http:" open redirect), and any `?skin=` is dropped with the
  # rest of the query, or it would override the choice just saved.
  def return_path
    path = params[:return_to].to_s
    local = path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
    local ? path.split(/[?#]/, 2).first : root_path
  end
end
