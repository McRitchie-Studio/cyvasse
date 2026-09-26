module MatchesHelper
  # One line on My games saying where a match stands for `user`.
  def match_summary(match, user)
    opponent = match.opponent_of(user).username
    case match.match_status
    when Match::PENDING
      match.seat(user) == :away ? "#{opponent} challenged you" : "challenge sent, awaiting #{opponent}"
    when Match::ACCEPTED
      match.ready?(user) ? "your army is in; #{opponent} is setting up" : "set up your army"
    when Match::IN_PROGRESS
      due = match.deadline ? " · due #{time_ago_in_words(match.deadline)} from now" : ""
      (match.your_turn?(user) ? "turn #{match.turn}, your move" : "turn #{match.turn}, #{opponent} to move") + due
    else
      finished_summary(match, user)
    end
  end

  private

  def finished_summary(match, user)
    return "draw" if match.finish_reason == "draw"
    return "expired unplayed" if match.finish_reason == "expired"
    return "left unfinished" if match.finish_reason == "abandoned"
    return "finished" if match.winner_id.nil?

    won = match.winner_id == user.id
    how = { "king" => "king captured", "resigned" => "resigned", "forfeit" => "out of time" }[match.finish_reason]
    [ won ? "won" : "lost", how && "(#{how})", "at turn #{match.turn}" ].compact.join(" ")
  end
end
