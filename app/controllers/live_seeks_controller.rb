# Play Now (task play-now-matchmaking). POST /live starts a search, signing a
# visitor in as a guest if need be; GET /live/:id is the searching page, and
# its JSON is what that page polls each second until a match is made (another
# live player, or a computer player once the search time is up). POST
# /live/:id/computer is "Play the computer now".
class LiveSeeksController < ApplicationController
  skip_before_action :require_authentication, only: :create
  before_action :set_seek, only: %i[show computer]
  helper_method :splash_ms

  SPLASH = 5.seconds

  def create
    user = current_user || rescue_and_log { start_guest }
    return redirect_to(username_path, notice: "Choose a player name to play live.") if user.username.blank?

    redirect_to live_seek_path(rescue_and_log(target: user) { LiveSeek.join!(user) })
  end

  def show
    rescue_and_log(target: @seek, parent: current_user) { @seek.settle! }
    respond_to do |format|
      format.html
      format.json { render json: status_json }
    end
  end

  def computer
    rescue_and_log(target: @seek, parent: current_user) { @seek.settle!(computer: true) }
    respond_to do |format|
      format.html { redirect_to match_path(@seek.match) }
      format.json { render json: status_json }
    end
  end

  private

  def set_seek
    @seek = current_user.live_seeks.find(params[:id])
  end

  def start_guest
    guest = User.create_guest!
    set_app_session(guest)
    @current_user = guest
  end

  def status_json
    match = @seek.match
    return { status: "searching", ends_at: @seek.ends_at.iso8601(3), server_time: Time.current.iso8601(3) } unless match

    opponent = match.opponent_of(current_user)
    { status: "matched", match_url: match_path(match), you: current_user.username,
      opponent: match.display_name_of(opponent), computer: opponent.computer?, splash_ms: splash_ms }
  end

  def splash_ms
    ((Rails.configuration.x.live_splash_time.presence || SPLASH).to_f * 1000).round
  end
end
