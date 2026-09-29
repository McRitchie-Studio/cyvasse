# The leaderboards (task live-leaderboard-and-guest-claim): the landing
# page's top ten and /leaderboard.
#
# THE LIVE BOARD RULE (task cyvasse-leaderboard-points, 2026-09-29):
#
#   * Points: 1 for every finished live game (Match.live) plus 2 more for a
#     win, so a win is 3 and a loss or a draw is 1. Read from the matches on
#     every request, so a game counts the moment it ends.
#   * A game counts when it ended with a result: a king fell, a resignation, a
#     forfeit on the move clock, or a draw. A match that expired before play
#     is not a game.
#   * Games against a computer player count, won or lost.
#   * A seat a computer held counts for nobody: a computer player's, and a
#     human seat a computer took over after missed clocks (Match#on_record?).
#   * Guests appear under their guest name. Signing in moves their matches to
#     the account (GuestClaim), so the points follow; a guest already merged
#     never appears.
#   * Rank: most points, then most wins, then whoever reached the score first
#     (their last counted game ended earlier).
#
# The ALL-TIME board is the won/lost record on the account (users.wins and
# users.losses): the old site's totals, carried over by LegacyImport, plus
# every result since (Match#finish!). People only, ranked by wins, then
# fewest losses, then the longest-standing account.
class Leaderboard
  Row = Data.define(:rank, :user, :points, :wins, :games, :losses)

  LIVE_SIZE = 10
  PAGE_SIZE = 50
  GAME_POINTS = 1
  WIN_POINTS = 3
  COUNTED_ENDINGS = %w[king resigned forfeit draw].freeze

  def self.points(games:, wins:) = (games * GAME_POINTS) + (wins * (WIN_POINTS - GAME_POINTS))

  # The live board, best first. `limit: nil` is every row.
  def self.live(limit: LIVE_SIZE)
    rows(User.from(ranked.arel.as("users")).select("users.*").order("users.board_rank").limit(limit))
  end

  # A player's live row (rank, points, wins, games), or nil when they are not
  # on the board. For the navbar (task cyvasse-nav-links).
  def self.rank_for(user)
    return if user.nil?

    rows(User.from(ranked.arel.as("users")).select("users.*").where(id: user.id)).first
  end

  def self.all_time(limit: PAGE_SIZE)
    scope = User.ranked_players.where("users.wins > 0")
                .select("users.*, users.wins AS board_wins, users.losses AS board_losses, " \
                        "users.wins + users.losses AS board_games")
                .order(wins: :desc, losses: :asc, created_at: :asc, id: :asc)
    scope.limit(limit).to_a.each_with_index.map do |user, i|
      Row.new(rank: i + 1, user:, points: nil, wins: user.wins, games: user.board_games.to_i, losses: user.losses)
    end
  end

  def self.rows(scope)
    scope.to_a.map do |user|
      Row.new(rank: user.board_rank.to_i, user:, points: user.board_points.to_i, wins: user.board_wins.to_i,
              games: user.board_games.to_i, losses: user.board_losses.to_i)
    end
  end
  private_class_method :rows

  # Every player on the live board with their numbers and board_rank.
  def self.ranked
    records = live_records.arel.as("records")
    join = Arel::Nodes::InnerJoin.new(records, Arel::Nodes::On.new(records[:user_id].eq(User.arel_table[:id])))
    order = "records.points DESC, records.wins DESC, records.reached_at ASC, users.id ASC"
    live_players.joins(join).select(
      "users.*", "records.points AS board_points", "records.wins AS board_wins",
      "records.games AS board_games", "records.losses AS board_losses",
      "ROW_NUMBER() OVER (ORDER BY #{order}) AS board_rank"
    )
  end
  private_class_method :ranked

  # People and unmerged guests with a username; never a computer player.
  def self.live_players
    User.where(merged_into_id: nil).where.not(username: [ nil, "" ])
        .where("users.legacy_id IS NULL OR users.legacy_id NOT BETWEEN ? AND ?",
               User::COMPUTER_LEGACY_IDS.first, User::COMPUTER_LEGACY_IDS.last)
  end
  private_class_method :live_players

  # One row per player: games, wins, losses, points, and when they reached
  # that score. Each counted live match is split into its two seats; a bot
  # seat is dropped, so its result reaches nobody.
  def self.live_records
    finished = Match.live.finished.where(finish_reason: COUNTED_ENDINGS)
    ended_at = "COALESCE(matches.finished_at, matches.updated_at) AS ended_at"
    home = finished.select("matches.home_user_id AS user_id", "matches.home_bot AS bot", "matches.winner_id", ended_at)
    away = finished.select("matches.away_user_id AS user_id", "matches.away_bot AS bot", "matches.winner_id", ended_at)
    seats = Arel::Nodes::UnionAll.new(home.arel, away.arel)
    wins = "COUNT(*) FILTER (WHERE seats.winner_id = seats.user_id)"

    Match.unscoped.from(Arel::Nodes::TableAlias.new(Arel::Nodes::Grouping.new(seats), "seats"))
         .where("NOT seats.bot")
         .group("seats.user_id")
         .select("seats.user_id",
                 "COUNT(*) AS games",
                 "#{wins} AS wins",
                 "COUNT(*) FILTER (WHERE seats.winner_id IS NOT NULL AND seats.winner_id <> seats.user_id) AS losses",
                 "COUNT(*) * #{GAME_POINTS} + #{wins} * #{WIN_POINTS - GAME_POINTS} AS points",
                 "MAX(seats.ended_at) AS reached_at")
  end
  private_class_method :live_records
end
