# Live matches (task live-match-engine): short clocks for a game played in one
# sitting, strikes for missed clocks, and computer seats that stand in for a
# player who is not there (a bot opponent, or a player who timed out twice).
class AddLivePlayToMatches < ActiveRecord::Migration[8.1]
  def change
    change_table :matches, bulk: true do |t|
      t.boolean :live, null: false, default: false
      t.datetime :clock_started_at
      t.datetime :bot_due_at
      t.integer :home_strikes, null: false, default: 0
      t.integer :away_strikes, null: false, default: 0
      t.boolean :home_bot, null: false, default: false
      t.boolean :away_bot, null: false, default: false
      t.boolean :home_auto_set_up, null: false, default: false
      t.boolean :away_auto_set_up, null: false, default: false
    end
  end
end
