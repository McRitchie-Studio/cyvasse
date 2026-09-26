# Saved army lineups (epic cyvasse-revival piece 10b): a player names the army
# they have placed and saves it to one of three slots, then loads it into any
# later setup, against the computer or online.
#
# The legacy setups table (amcritchie/Cyvasse db/schema.rb) was
#
#   user_id          integer   the owner
#   name             string    what they called it (the legacy prompt allowed 20)
#   units_position   string    the army from the owner's own seat, the legacy
#                              "unitIndex:hex|" string (hexes 52-91)
#   button_position  integer   the slot, 1-3
#   created_at, updated_at
#
# Every column is kept under its legacy name, so the importer brings the 5,004
# legacy rows over one to one. user_id is a real foreign key, mapped through
# users.legacy_id, and a player's lineups go with them. legacy_id holds the
# legacy setups.id, unique, so a re-run skips what it already brought over.
#
# The legacy save destroyed the slot's lineup and created a new one, which did
# not always land: some players hold two rows in one slot. They all import; the
# newest in a slot is the one a player sees (Setup.slots_for).
class CreateSetups < ActiveRecord::Migration[8.1]
  def change
    create_table :setups do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name
      t.string :units_position, null: false
      t.integer :button_position, null: false
      t.integer :legacy_id

      t.timestamps
    end

    add_index :setups, [ :user_id, :button_position ]
    add_index :setups, :legacy_id, unique: true
  end
end
