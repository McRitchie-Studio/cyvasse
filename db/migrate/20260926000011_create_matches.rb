# Online matches between two players (epic cyvasse-revival piece 6).
#
# The columns above the line are the legacy matches table verbatim, names and
# types (amcritchie/Cyvasse db/schema.rb), so piece 10 can import the 107,941
# legacy matches without a mapping:
#
#   match_status          pending -> new -> in progress -> finished
#   home/away_units_position  "unitIndex:location|" x 19, both armies from
#                          the home seat (away on hexes 1-40); location is a
#                          hex, g<team> for a captured unit, lDock unplaced
#   whos_turn, who_started 1 = home, 0 = away
#   last_move              "from,to" in the home frame
#   utility_saved_hex      a cavalry unit's first-jump origin (legacy "95" = none)
#   time_of_last_move      starts the seven-day move clock
#
# Legacy nullability is kept too (only the two players are required, and the
# model validates the rest), because legacy rows carry nulls: fast_game was
# never written, for one.
#
# Below the line are the two things the legacy app never stored: who won and
# why the match ended. Legacy rows leave them null.
class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.references :home_user, null: false, foreign_key: { to_table: :users }
      t.references :away_user, null: false, foreign_key: { to_table: :users }
      t.integer :turn, default: 0
      t.integer :who_started
      t.string :match_status, default: "pending"
      t.string :match_against, default: "human"
      t.string :home_units_position
      t.string :away_units_position
      t.integer :whos_turn
      t.boolean :home_ready, default: false
      t.boolean :away_ready, default: false
      t.string :last_move
      t.datetime :time_of_last_move
      t.string :utility_saved_hex
      t.boolean :fast_game, default: false
      # ---- not in the legacy table
      t.references :winner, foreign_key: { to_table: :users }
      t.string :finish_reason

      t.timestamps
    end
    add_index :matches, [ :match_status, :time_of_last_move ]
  end
end
