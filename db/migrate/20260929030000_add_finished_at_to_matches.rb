# When a match ended (task live-leaderboard-and-guest-claim): the live
# leaderboard breaks a tie on wins and losses by the most recent win, and
# updated_at is not a finish time. Live matches only exist from the relaunch,
# so the column needs no backfill (the board reads updated_at for a blank).
class AddFinishedAtToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :finished_at, :datetime
    add_index :matches, [ :live, :match_status ], name: "index_matches_on_live_and_match_status"
  end
end
