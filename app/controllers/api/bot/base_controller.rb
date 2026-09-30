# The remote runner's door (task tyrion-bot-api): a computer player's program,
# running off the server, plays that account's matches over JSON. It
# authenticates with `Authorization: Bearer <token>` (BotToken), never a
# session or cookie, and every action is scoped to the token's own account,
# so it can do only what a signed-in player could do from a browser.
module Api
  module Bot
    class BaseController < ActionController::API
      include ActionController::MimeResponds
      include ActionController::Helpers
      include Studio::ErrorHandling

      skip_before_action :require_authentication
      before_action :authenticate_bot!

      # Counted in Rails.cache (per dyno); the test environment's null store
      # never counts, so tests get a store of their own. A runner polling
      # every two seconds uses about 60 a minute.
      RATE_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
      RATE = 300
      rate_limit to: RATE, within: 1.minute, store: RATE_STORE,
                 by: -> { BotToken.digest(bearer_token) },
                 with: -> { render json: { error: "rate limited" }, status: :too_many_requests }

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not found" }, status: :not_found
      end

      private

      def current_user = @current_user

      def authenticate_bot!
        token = BotToken.authenticate(bearer_token)
        return render(json: { error: "unauthenticated" }, status: :unauthorized) unless token

        token.heard!
        @current_user = token.user
      end

      def bearer_token
        request.authorization.to_s[/\ABearer (\S+)\z/, 1]
      end

      def find_match(id)
        Match.involving(current_user).includes(:home_user, :away_user).find(id)
      end

      # A live match's clocks and computer seats settle when a board asks
      # (LiveMatch#tick!), as MatchesController does for a browser.
      def settle(match)
        return match unless match.live?

        rescue_and_log(target: match) { match.tick! }
        match
      rescue StandardError
        match.reload
      end
    end
  end
end
