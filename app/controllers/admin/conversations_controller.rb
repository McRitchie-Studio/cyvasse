# Every conversation that ever happened (epic cyvasse-revival piece 12; Alex:
# "an admin page with all the conversations that ever happened"). Newest
# first, searchable by player (username, name or email), a page at a time,
# each linking its matches. The About page tells players admins can read them.
module Admin
  class ConversationsController < BaseController
    def index
      @query = params[:q].to_s.strip
      @page = Conversation.page(Conversation.for_players(@query, Message.with_text), page: params[:page])
    end

    # One conversation's whole thread, grouped by the game each message was
    # sent in (piece 12b): a page of games, newest first, or with ?game= one
    # game (a match id, or "none" for messages outside any) page by page.
    # :id is the pair, "low-high" user ids; the low user's bubbles sit left.
    def show
      low, high = Conversation.parse_key(params[:id])
      raise ActiveRecord::RecordNotFound, "bad conversation key" unless low

      @users = User.where(id: [ low, high ]).index_by(&:id).values_at(low, high)
      raise ActiveRecord::RecordNotFound, "no such players" if @users.any?(&:nil?)

      thread = ConversationThread.new(*@users)
      @total = thread.total
      raise ActiveRecord::RecordNotFound, "no conversation" if @total.zero?

      @game = params[:game].presence
      @page = @game ? thread.game(@game, page: params[:page]) : thread.page(params[:page])
      raise ActiveRecord::RecordNotFound, "no such game in this conversation" unless @page
    end
  end
end
