# Synthetic players, matches and messages for a desk or a local demo of the
# inbox and the admin Conversations page (epic cyvasse-revival piece 12).
# Every name and line is made up; the real legacy messages arrive with the
# import (piece 10b) and are never used here.
#
# Idempotent: players are found by email, and a pair that already has
# messages is left alone. Refuses to run in production. db/seeds.rb calls it
# in development; `bin/rails messages:demo` runs it on its own.
module DemoConversations
  PLAYERS = %w[
    arya_stark brienne tyrion_l daenerys jon_snow sansa_s oberyn_m
    cersei_l jaime_l sam_tarly bran_s theon_g davos margaery
  ].freeze

  LINES = [
    "Good game! That elephant rush caught me off guard.",
    "Rematch? I want to try a mountain wall this time.",
    "Your dragon keeps flying over my trebuchets, rude.",
    "How did you get your cavalry across so fast?",
    "I think the crossbow range is the most underrated rule.",
    "Sorry for the slow move, busy week. Your turn now.",
    "That was the closest game I have played in a while.",
    "Do you open with the king behind the mountains every time?",
    "gg, the spearmen held better than I expected",
    "Want to play a fast game this weekend?",
    "I resigned too early, I think I had a draw there.",
    "Nice light horse double jump, did not see it coming."
  ].freeze

  module_function

  # Returns the number of messages created.
  def seed!(now: Time.current, env: Rails.env)
    raise "DemoConversations never runs in production" if env.production?

    players = PLAYERS.map do |username|
      User.find_or_create_by!(email: "#{username}@example.com") do |user|
        user.name = username.titleize
        user.username = username
      end
    end
    alex = User.find_by(email: "alex@mcritchie.studio")
    alex.update!(username: "alex_mcritchie") if alex && alex.username.blank?
    players.unshift(alex) if alex

    created = 0
    players.combination(2).each_with_index do |(one, other), n|
      next unless n % 3 == 0 || one == alex
      next if Message.between(one, other).exists?

      created += converse(one, other, n, now - (n * 5).hours)
    end
    created
  end

  def converse(one, other, n, last_at)
    # Finished matches only: a demo match has no armies on its board, so one
    # left in play could never be played on.
    match = Match.create!(home_user: one, away_user: other, match_status: Match::FINISHED,
                          winner: n.even? ? one : other, finish_reason: n.even? ? "king" : "resigned",
                          turn: 10 + n, time_of_last_move: last_at)
    count = 2 + (n % 4)
    count.times do |i|
      sender, receiver = i.even? ? [ one, other ] : [ other, one ]
      at = last_at - ((count - i) * 17).minutes
      Message.create!(sender: sender, receiver: receiver, match: i.zero? && n % 5 == 0 ? nil : match,
                      message: LINES[(n + i) % LINES.size], read: i < count - 1, created_at: at, updated_at: at)
    end
    count
  end
end
