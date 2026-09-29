# One of the runner's own matches: its state from the runner's seat, its army,
# and its turns, answered exactly as MatchesController answers the board
# (Match#set_up! and Match#play! check them by the engine's rules). Anyone
# else's match is a 404.
module Api
  module Bot
    class MatchesController < BaseController
      before_action { @match = find_match(params[:id]) }

      def show
        render json: settle(@match).state_for(current_user)
      end

      # { lineup: "unitIndex:hex|..." } from the runner's own seat.
      def set_up
        answer attempt { @match.set_up!(current_user, params[:lineup]) }
      end

      # { steps: [[from, to]] or [[from, to], [from, to]] } from its own seat.
      def move
        answer attempt { @match.play!(current_user, params[:steps]) }
      end

      private

      def attempt
        rescue_and_log(target: current_user, parent: @match) do
          yield
          nil
        rescue Match::Refused => e
          e.message
        end
      end

      def answer(error)
        state = settle(@match.reload).state_for(current_user)
        if error
          render json: { error:, state: }, status: :unprocessable_entity
        else
          render json: { state: }
        end
      end
    end
  end
end
