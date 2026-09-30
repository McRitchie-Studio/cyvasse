# One page of a conversation as the chat shows it (task cyvasse-live-chat):
# the pair's messages across every match and none, oldest first, read
# through index_messages_on_conversation. The Chat hub's thread and the match
# chat both show one, so a conversation carries on from match to match.
#
#   ChatThread.new(viewer, other)                 the latest SHOWN
#   ChatThread.new(viewer, other, before: id)     the SHOWN before message id
#   ChatThread.new(viewer, other, after: id)      everything since message id
#                                                 (a reconnected page catching up)
class ChatThread
  SHOWN = 50

  attr_reader :viewer, :other

  def initialize(viewer, other, before: nil, after: nil, limit: SHOWN)
    @viewer = viewer
    @other = other
    @before = before.presence && Integer(before.to_s, 10, exception: false)
    @after = after.presence && Integer(after.to_s, 10, exception: false)
    @limit = limit
  end

  def scope
    Message.in_pair(viewer.id, other.id).with_text
  end

  def messages
    load
    @messages
  end

  # Whether older messages remain before the first one shown.
  def earlier?
    load
    @earlier
  end

  def first_id = messages.first&.id

  def empty? = messages.empty?

  def unread? = scope.unread_by(viewer).exists?

  def dom_id = ChatStreams.thread_id(viewer, other)

  private

  def load
    return if defined?(@messages)

    if @after
      @messages = scope.where("messages.id > ?", @after).reorder(:created_at, :id).limit(@limit).includes(:sender, :match).to_a
      @earlier = false
    else
      rows = older_than_cursor(scope).reorder(created_at: :desc, id: :desc).limit(@limit + 1).includes(:sender, :match).to_a
      @earlier = rows.size > @limit
      @messages = rows.first(@limit).reverse
    end
  end

  # Ordered by (created_at, id), as the thread is shown: imported legacy rows
  # do not have ids in the order they were sent.
  def older_than_cursor(relation)
    return relation unless @before

    cursor = Message.where(id: @before).pick(:created_at)
    return relation.none unless cursor

    relation.where("(messages.created_at, messages.id) < (?, ?)", cursor, @before)
  end
end
