# One match as an admin sees it (epic cyvasse-revival piece 12): its players,
# where it stands, and its chat. Linked from the admin Conversations page.
module Admin
  class MatchesController < BaseController
    def show
      @match = Match.includes(:home_user, :away_user, :winner).find(params[:id])
      @messages = @match.messages.with_text.chronological.includes(:sender).to_a
    end
  end
end
