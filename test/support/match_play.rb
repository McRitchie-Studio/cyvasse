# Shared by the match tests: two players and a real recorded game to play.
#
# The game is one the JavaScript engine played itself
# (test/fixtures/files/rules_agreement.json, game 5: home moves first, away
# wins at turn 28), so every step posted below is one the browser would offer.
module MatchPlay
  RECORD = JSON.parse(Rails.root.join("test/fixtures/files/rules_agreement.json").read)
  GAME = RECORD.fetch("games").fetch(5)

  def mirror(hex) = CyvasseRules::Board.mirror(hex)

  def make_player(name, email: "#{name.downcase}@example.com")
    User.create!(email:, name: name.titleize, username: name)
  end

  # The home army as the home player submits it (their seat is the home frame).
  def home_lineup = GAME.fetch("home")

  # The away army as the away player submits it: from their own seat, i.e.
  # the recorded home-frame lineup turned round.
  def away_lineup
    CyvasseRules::Game.format(CyvasseRules::Game.parse(GAME.fetch("away"), 0).map { |u| [ u.index, mirror(u.hex) ] })
  end

  # A recorded turn's steps from the mover's own seat.
  def steps_for(turn)
    steps = turn.fetch("steps")
    turn.fetch("mover") == Match::AWAY ? steps.map { |s| s.map { mirror(_1) } } : steps
  end

  def started_match(home, away)
    match = Match.challenge!(home, away.username)
    match.accept!(away)
    match.set_up!(home, home_lineup)
    match.set_up!(away, away_lineup)
    match
  end
end
