# The leaderboards (task live-leaderboard-and-guest-claim): the landing
# page's top ten and /leaderboard.
#
# THE LIVE BOARD RULE (decided for the relaunch, 2026-09-29):
#
#   * It counts wins in LIVE matches (Match.live): the Play Now games from the
#     relaunch on. There is no date cutoff, because live matches only exist
#     from the relaunch.
#   * A win counts only for a person's own seat: a human seat that no computer
#     took over. A computer player's win never counts, and a win by a
#     stand-in (a computer that took a seat over after missed clocks) counts
#     for nobody, not even the player whose seat it was.
#   * A win over a computer player DOES count, so the board is not empty at
#     launch.
#   * Computer players and guests never appear on the board (they may still be
#     the opponent). A guest's wins count once they sign in and claim them
#     (GuestClaim), because the matches move to their account.
#   * A loss is a finished live match, won by the other side, in a seat the
#     player kept; a seat a computer took over loses for nobody either, as on
#     the won/lost record (Match#on_record?).
#   * Rank: most wins, then fewest losses, then the most recent win.
#
# The ALL-TIME board is the won/lost record on the account (users.wins and
# users.losses): the old site's totals, carried over by LegacyImport, plus
# every result since (Match#finish!). People only, ranked the same way, then
# by the longest-standing account.
class Leaderboard
  Row = Data.define(:rank, :user, :wins, :losses)

  LIVE_SIZE = 10
  PAGE_SIZE = 50

  # A person's live wins and losses, with at least one win. `limit: nil` is
  # every row.
  def self.live(limit: LIVE_SIZE)
    scope = User.ranked_players
                .joins("INNER JOIN (#{live_records_sql}) records ON records.user_id = users.id")
                .where("records.wins > 0")
                .select("users.*, records.wins AS board_wins, records.losses AS board_losses")
                .order(Arel.sql("records.wins DESC, records.losses ASC, records.last_win_at DESC, users.id ASC"))
    rows(scope.limit(limit))
  end

  def self.all_time(limit: PAGE_SIZE)
    scope = User.ranked_players.where("users.wins > 0")
                .select("users.*, users.wins AS board_wins, users.losses AS board_losses")
                .order(wins: :desc, losses: :asc, created_at: :asc, id: :asc)
    rows(scope.limit(limit))
  end

  def self.rows(scope)
    scope.to_a.each_with_index.map do |user, i|
      Row.new(rank: i + 1, user:, wins: user.board_wins.to_i, losses: user.board_losses.to_i)
    end
  end
  private_class_method :rows

  # One row per player with their live wins, losses and latest win. Each
  # finished live match is split into its two seats; a bot seat (a computer
  # player from the start, or a stand-in after missed clocks) is dropped, so
  # neither its wins nor its losses reach anyone.
  def self.live_records_sql
    finished = Match.live.finished
    seat = lambda do |side|
      finished.select(
        "matches.#{side}_user_id AS user_id", "matches.#{side}_bot AS bot", "matches.winner_id",
        "COALESCE(matches.finished_at, matches.updated_at) AS ended_at"
      ).to_sql
    end
    <<~SQL.squish
      SELECT seats.user_id,
             COUNT(*) FILTER (WHERE seats.winner_id = seats.user_id) AS wins,
             COUNT(*) FILTER (WHERE seats.winner_id IS NOT NULL AND seats.winner_id <> seats.user_id) AS losses,
             MAX(seats.ended_at) FILTER (WHERE seats.winner_id = seats.user_id) AS last_win_at
      FROM (#{seat.call(:home)} UNION ALL #{seat.call(:away)}) seats
      WHERE NOT seats.bot
      GROUP BY seats.user_id
    SQL
  end
  private_class_method :live_records_sql
end
