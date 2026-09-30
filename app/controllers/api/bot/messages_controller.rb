# The runner's line in one of its own matches' chat, under the ordinary
# message rules (Message.post_in_match!: text present, at most 1,000
# characters, to the match's other player).
module Api
  module Bot
    class MessagesController < BaseController
      def create
        match = find_match(params[:match_id])
        message = rescue_and_log(target: current_user, parent: match) do
          Message.post_in_match!(match, current_user, params[:message])
        rescue ActiveRecord::RecordInvalid => e
          e.record
        end

        if message.persisted?
          render json: { id: message.id }, status: :created
        else
          render json: { error: message.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end
    end
  end
end
