# What the runner has to do: the unfinished matches it plays (with the action
# each waits on from it) and the chat messages sent to it in them since
# `after` (a message id; the answer's `cursor` is the next one to pass).
# A live seat the in-app computer holds (Play Now's `away_bot`, or a seat
# taken over after missed clocks) is not the runner's, so neither it nor its
# chat is listed. Polling this is also the runner's heartbeat (BotToken#heard!).
module Api
  module Bot
    class InboxController < BaseController
      MESSAGES = 50

      def show
        matches = Match.involving(current_user).active.includes(:home_user, :away_user).order(:id)
                       .reject { |m| in_app_seat?(m) }.map { |m| settle(m) }
        messages = Message.where(receiver: current_user, match_id: matches.map(&:id)).with_text.where(id: (params[:after].to_i + 1)..)
                          .order(:id).limit(MESSAGES).includes(:sender).to_a

        render json: {
          matches: matches.map { |match| summary(match) },
          messages: messages.map { |m| { id: m.id, match_id: m.match_id, from: m.sender.username, text: m.message, sent_at: m.created_at.iso8601 } },
          cursor: messages.last&.id || params[:after].to_i
        }
      end

      private

      def in_app_seat?(match) = match.live? && match.bot_seat?(match.seat(current_user))

      def summary(match)
        state = match.state_for(current_user)
        action = if state[:can_set_up] then "setup" elsif state[:your_turn] then "move" end
        { id: match.id, live: match.live?, phase: state[:phase], action:, opponent: state.dig(:opponent, :username), deadline: state[:deadline] }
      end
    end
  end
end
