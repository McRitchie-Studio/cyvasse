# A player's Chat hub (epic cyvasse-revival piece 12; task cyvasse-live-chat):
# their conversations with people, newest first, the people they have played
# and not yet messaged, and each conversation's whole thread, across every
# match and none, updating live (ChatBroadcasts).
#
# A conversation is addressed by the other player's user id (not their slug,
# which is drawn from their real name) and is visible to its two people
# alone. It opens when there are messages between you, or when you may start
# one (User#can_message?); otherwise it is a 404. Sending always follows
# User#can_message?, so a legacy conversation with someone you never played
# stays readable but takes no reply.
class ConversationsController < ApplicationController
  include ChatSending

  # People played but not yet messaged, listed under "Say hi".
  SAY_HI = 20

  before_action :set_other, except: :index
  rate_limit_sending only: :reply

  def index
    @page = Conversation.hub(current_user, page: params[:page])
    @say_hi = @page.page == 1 ? say_hi : []
  end

  def show
    @thread = ChatThread.new(current_user, @other)
    rescue_and_log(target: current_user, parent: @other) { Message.mark_read!(@thread.scope, current_user, other: @other) }
  end

  # A message outside any match: a reply, or the first message to someone
  # played. Refused unless User#can_message?.
  def reply
    send_message(chat_thread_id) { Message.send_direct!(current_user, @other, params[:message]) }
  end

  # Older messages for the thread's "Load earlier" frame (?before=<id>), or
  # the messages since one (?after=<id>) as a Turbo Stream, for a page whose
  # socket dropped and came back.
  def messages
    if params[:after].present?
      @thread = ChatThread.new(current_user, @other, after: params[:after])
      render :since, formats: :turbo_stream
    else
      @thread = ChatThread.new(current_user, @other, before: params[:before])
      @frame_id = "chat_earlier_#{@thread.dom_id}_#{params[:before].to_i}"
      render :earlier
    end
  end

  # The thread is on screen: mark it read (the chat controller calls this as
  # messages arrive while the reader is looking).
  def read
    rescue_and_log(target: current_user, parent: @other) do
      Message.mark_read!(ChatThread.new(current_user, @other).scope, current_user, other: @other)
    end
    head :no_content
  end

  private

  def set_other
    @other = User.find(params[:id])
    readable = @other.id != current_user.id &&
               (Message.in_pair(current_user.id, @other.id).with_text.exists? || current_user.can_message?(@other))
    raise ActiveRecord::RecordNotFound, "no conversation" unless readable
  end

  def chat_thread_id = ChatStreams.thread_id(current_user, @other)

  def after_send_path = conversation_path(@other.id, anchor: "latest")

  # The people played, newest match first, with no messages yet.
  def say_hi
    talked = Message.involving(current_user).with_text
                    .pluck(Arel.sql("DISTINCT #{Conversation::PAIR_LOW}"), Arel.sql(Conversation::PAIR_HIGH)).flatten.to_set
    current_user.played_humans.reject { |person| talked.include?(person.id) }.first(SAY_HI)
  end
end
