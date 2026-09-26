# Online play needs a public name: players find and challenge each other by
# username. A signed-in player without one is sent to choose it first, then
# brought back.
module RequiresUsername
  extend ActiveSupport::Concern

  private

  def require_username
    return if current_user&.username.present?

    respond_to do |format|
      format.html { redirect_to username_path(return_to: request.fullpath), notice: "Choose a username to play online." }
      format.json { render json: { error: "Choose a username first." }, status: :forbidden }
    end
  end

  # Only a local path is honoured as a return address (no "//host" redirect).
  def safe_return_path(path, fallback)
    path = path.to_s
    path.start_with?("/") && !path.start_with?("//") && !path.include?("\\") ? path : fallback
  end
end
