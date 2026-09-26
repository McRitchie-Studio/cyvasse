# The legacy import (epic cyvasse-revival piece 10a) keeps each row's id from
# the old cyvasse-game database. It is what makes the import idempotent (a
# rerun skips every legacy id already present) and what later pieces map
# through: legacy messages and setups name their players and matches by these
# ids. Null on every row created in the new app.
class AddLegacyIdToUsersAndMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :legacy_id, :integer
    add_index :users, :legacy_id, unique: true
    add_column :matches, :legacy_id, :integer
    add_index :matches, :legacy_id, unique: true
  end
end
