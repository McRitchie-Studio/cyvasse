# The live chat's view helpers (task cyvasse-live-chat).
module ChatHelper
  # Whether the match page shows its chat: always against a person; against
  # a computer player only while its remote runner reads the chat (a live
  # bot token, as Tyrion's) and the in-app computer is not playing its seat
  # (Play Now's), which reads nothing.
  def match_chat?(match, opponent)
    return true unless opponent.computer?

    BotToken.active.exists?(user: opponent) && !match.bot_seat?(match.seat(opponent))
  end
end
