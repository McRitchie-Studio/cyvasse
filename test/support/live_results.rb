# Finished live matches for the leaderboard and guest-claim tests, written
# straight to the table: the rule reads only who sat where, whether a seat was
# a computer's (a computer player, or a stand-in after missed clocks), and who
# won.
module LiveResults
  def player(name, **attrs)
    User.create!(email: "#{name.downcase}@example.com", name: name.titleize, username: name, **attrs)
  end

  def computer(seed = 1)
    Match.computer_player(rng: Random.new(seed))
  end

  # home_bot/away_bot: a computer in that seat. For a human seat, pass
  # strikes: 2 too, as a take-over leaves it.
  def live_result(home, away, winner:, finished_at: Time.current, live: true, finish_reason: (winner ? "king" : "draw"), **seats)
    Match.create!(home_user: home, away_user: away, winner:, live:, match_status: Match::FINISHED,
                  finish_reason:, finished_at:, time_of_last_move: finished_at,
                  match_against: "human", home_ready: true, away_ready: true, turn: 20,
                  away_bot: away.computer?, **seats)
  end
end
