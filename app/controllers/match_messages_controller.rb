# The chat on a match (epic cyvasse-revival piece 12). Its two players read
# and write it; anyone else gets a 404, as for the match itself.
#
# The match page shows the messages in a Turbo frame (match_chat_messages)
# that loads from #index and reloads itself while the page is open; the form
# beside it posts to #create, which answers with the same frame.
class MatchMessagesController < ApplicationController
  include RequiresUsername

  SHOWN = 100

  before_action :require_username
  before_action :set_match

  def index
    rescue_and_log(target: current_user, parent: @match) { Message.mark_read!(@match.messages, current_user) }
    load_messages
  end

  def create
    error = nil
    rescue_and_log(target: current_user, parent: @match) do
      Message.post_in_match!(@match, current_user, params[:message])
    rescue ActiveRecord::RecordInvalid => e
      error = e.record.errors.full_messages.to_sentence
    end

    if error
      @error = error
      load_messages
      render :index, status: :unprocessable_entity
    else
      redirect_to match_messages_path(@match), status: :see_other
    end
  end

  private

  def set_match
    @match = Match.involving(current_user).includes(:home_user, :away_user).find(params[:match_id])
  end

  def load_messages
    @messages = @match.messages.order(created_at: :desc, id: :desc).limit(SHOWN).includes(:sender).to_a.reverse
  end
end
