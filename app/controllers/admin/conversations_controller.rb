# Every conversation that ever happened (epic cyvasse-revival piece 12; Alex:
# "an admin page with all the conversations that ever happened"). Newest
# first, searchable by player (username, name or email), a page at a time,
# each linking its matches. The About page tells players admins can read them.
module Admin
  class ConversationsController < BaseController
    SHOWN = 500

    def index
      @query = params[:q].to_s.strip
      @page = Conversation.page(Conversation.for_players(@query), page: params[:page])
    end

    # One conversation's whole thread. :id is the pair, "low-high" user ids.
    def show
      low, high = Conversation.parse_key(params[:id])
      raise ActiveRecord::RecordNotFound, "bad conversation key" unless low

      @users = User.where(id: [ low, high ]).index_by(&:id).values_at(low, high)
      raise ActiveRecord::RecordNotFound, "no such players" if @users.any?(&:nil?)

      messages = Message.between(*@users)
      @total = messages.count
      raise ActiveRecord::RecordNotFound, "no conversation" if @total.zero?

      @thread = messages.reorder(created_at: :desc, id: :desc).limit(SHOWN).includes(:sender, :match).to_a.reverse
    end
  end
end
