# A player's inbox (epic cyvasse-revival piece 12): their conversations,
# newest first, and each one's whole thread, across every match and none.
# A conversation is addressed by the other player's user id (not their slug,
# which is drawn from their real name) and is visible to
# its two people alone: with no messages between you, it is a 404.
class ConversationsController < ApplicationController
  SHOWN = 200

  before_action :set_other_and_messages, only: %i[show reply]

  def index
    @page = Conversation.page(Message.involving(current_user).with_text, page: params[:page], reader: current_user)
  end

  def show
    rescue_and_log(target: current_user, parent: @other) { Message.mark_read!(@messages, current_user) }
    load_thread
  end

  # A reply outside any match, as the legacy inbox sent them.
  def reply
    message = Message.new(sender: current_user, receiver: @other, message: params[:message].to_s.strip)
    saved = rescue_and_log(target: current_user, parent: @other) { message.save }
    if saved
      redirect_to conversation_path(@other.id, anchor: "latest"), status: :see_other
    else
      @error = message.errors.full_messages.to_sentence
      load_thread
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_other_and_messages
    @other = User.find(params[:id])
    @messages = Message.between(current_user, @other).with_text
    raise ActiveRecord::RecordNotFound, "no conversation" unless @messages.exists?
  end

  def load_thread
    @total = @messages.count
    @thread = @messages.reorder(created_at: :desc, id: :desc).limit(SHOWN).includes(:sender, :match).to_a.reverse
  end
end
