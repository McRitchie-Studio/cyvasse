# The chat's stream names (task cyvasse-live-chat), and who may hear each.
#
#   chat:user:<id>           one player's own stream: the navbar's unread
#                            badge and their Chat hub's rows
#   chat:pair:<low>-<high>   one conversation's stream: its new messages, for
#                            the hub thread and the match chat alike
#
# Pages subscribe through ChatStreamsChannel, which signs the name and then
# asks permitted?: a user stream is its own player's alone, a pair stream its
# two players' alone.
module ChatStreams
  USER = /\Achat:user:(\d+)\z/
  PAIR = /\Achat:pair:(\d+)-(\d+)\z/

  module_function

  def user(user) = "chat:user:#{user.id}"

  def pair(one, other)
    low, high = [ one.id, other.id ].minmax
    "chat:pair:#{low}-#{high}"
  end

  # The DOM id a conversation's thread list carries, on the hub thread and on
  # the match chat alike, so one broadcast appends to either.
  def thread_id(one, other) = "chat_thread_#{[ one.id, other.id ].minmax.join('_')}"

  def permitted?(name, user)
    return false if user.nil?

    if (match = USER.match(name))
      match[1].to_i == user.id
    elsif (match = PAIR.match(name))
      low, high = match[1].to_i, match[2].to_i
      low < high && [ low, high ].include?(user.id)
    else
      false
    end
  end
end
