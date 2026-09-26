# Online matches (epic cyvasse-revival piece 6): My Games, challenges, setup,
# turns and resigning. Signed-in players with a username only, and a match is
# visible to its two players alone (anyone else gets a 404).
#
# The browser plays from the player's own seat and posts whole turns; every
# one is checked on the server by Match#play! (CyvasseRules), and a refusal
# answers 422 with the match's true state so the board can redraw it.
class MatchesController < ApplicationController
  include RequiresUsername

  before_action :require_username
  before_action :expire_stale_matches, only: %i[index show]
  before_action :set_match, except: %i[index create]

  def index
    matches = Match.involving(current_user).includes(:home_user, :away_user)
    active = matches.active.order(time_of_last_move: :desc).to_a
    @your_move = active.select { |m| m.your_turn?(current_user) }
    @setup = active.select { |m| m.pregame? && !m.ready?(current_user) }
    @waiting = active - @your_move - @setup
    @finished = matches.finished.order(updated_at: :desc).limit(25).to_a
  end

  def show
    respond_to do |format|
      format.html do
        @state = @match.state_for(current_user)
        @opponent = @match.opponent_of(current_user)
        @piece_images = Piece.all.to_h { |piece| [ piece.slug, helpers.image_path(piece.image(current_skin)) ] }
      end
      format.json { render json: @match.state_for(current_user) }
    end
  end

  def create
    match = nil
    error = attempt { match = Match.challenge!(current_user, params[:username]) }
    if error
      redirect_to matches_path, alert: error, status: :see_other
    else
      redirect_to match_path(match), notice: "Challenge sent to #{match.away_user.username}. Set up your army while you wait.", status: :see_other
    end
  end

  def accept
    error = attempt { @match.accept!(current_user) }
    redirect_to match_path(@match), (error ? { alert: error } : { notice: "Challenge accepted. Set up your army." }).merge(status: :see_other)
  end

  # Decline or withdraw a challenge, before the first move.
  def destroy
    error = attempt { @match.withdraw!(current_user) }
    if error
      redirect_to match_path(@match), alert: error, status: :see_other
    else
      redirect_to matches_path, notice: "Match against #{@match.opponent_of(current_user).username} cancelled.", status: :see_other
    end
  end

  def resign
    error = attempt { @match.resign!(current_user) }
    redirect_to match_path(@match), (error ? { alert: error } : { notice: "You resigned." }).merge(status: :see_other)
  end

  # JSON from the board: { lineup: "unitIndex:hex|..." } from the player's seat.
  def set_up
    answer attempt { @match.set_up!(current_user, params[:lineup]) }
  end

  # JSON from the board: { steps: [[from, to]] or [[from, to], [from, to]] }.
  def move
    answer attempt { @match.play!(current_user, params[:steps]) }
  end

  private

  def set_match
    @match = Match.involving(current_user).find(params[:id])
  end

  # The clock is enforced whenever a player looks, so it holds with no
  # scheduler; `bin/rails matches:expire` sweeps the rest.
  def expire_stale_matches
    rescue_and_log(target: current_user) { Match.expire_stale!(Match.involving(current_user)) }
  end

  # Run a match change. A refusal (Match::Refused) is an answer for the
  # player, returned as its message; anything else is logged and raised.
  def attempt
    rescue_and_log(target: current_user, parent: @match) do
      yield
      nil
    rescue Match::Refused => e
      e.message
    end
  end

  def answer(error)
    state = @match.reload.state_for(current_user)
    if error
      render json: { error: error, state: state }, status: :unprocessable_entity
    else
      render json: { state: state }
    end
  end
end
