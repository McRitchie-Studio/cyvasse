# Online match mail (epic cyvasse-revival piece 6): a new challenge, and a
# nudge when it is your turn. Sent through the engine's outbox
# (Match#notify -> Studio::Email.deliver), so on a desk it lands in the local
# inbox at /_studio/local_emails instead of leaving the machine.
class MatchMailer < ApplicationMailer
  def challenged(match, user)
    @match = match
    @user = user
    @challenger = match.opponent_of(user)
    @url = match_url(match)
    @deadline = match.deadline
    mail(to: user.email, subject: "#{@challenger.username} challenges you to Cyvasse")
  end

  def your_turn(match, user)
    @match = match
    @user = user
    @opponent = match.opponent_of(user)
    @url = match_url(match)
    @deadline = match.deadline
    @first_move = match.turn.to_i <= 1
    mail(to: user.email, subject: "Your move against #{@opponent.username} · Cyvasse")
  end
end
