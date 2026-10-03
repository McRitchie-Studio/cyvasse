# The leaderboards (task live-leaderboard-and-guest-claim; the rule is in
# Leaderboard). Public, like the landing page that carries the top ten.
#
#   GET /leaderboard        the live board, or the all-time one (?board=all-time)
#   GET /leaderboard/join   a guest's sign-in, after a live game: the email
#                           link comes back with ?from_guest=1; the claim
#                           itself rides in this browser's session (GuestClaim)
class LeaderboardsController < ApplicationController
  include RequiresUsername

  skip_before_action :require_authentication

  BOARDS = %w[live all-time].freeze

  def show
    # Back from signing in with a claimed win: the board shows usernames only,
    # so an account without one chooses it first.
    if params[:from_guest].present? && current_user && !current_user.guest? && current_user.username.blank?
      return redirect_to(username_path(return_to: leaderboard_path), notice: "Choose a username for the leaderboard.")
    end

    @board = BOARDS.include?(params[:board]) ? params[:board] : "live"
    @rows = @board == "live" ? Leaderboard.live(limit: Leaderboard::PAGE_SIZE) : Leaderboard.all_time
  end

  def join
    return redirect_to(leaderboard_path) if current_user && !current_user.guest?

    @won = params[:result] == "win"
    back = current_user&.guest? ? { from_guest: 1 } : {}
    @return_to = @won ? leaderboard_path(back) : matches_path(back)
  end
end
