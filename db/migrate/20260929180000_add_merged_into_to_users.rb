# A guest absorbed by a signed-in account (GuestClaim, task
# cyvasse-game-over-signin). A guest with nothing left is deleted; one kept
# because it played the account itself is marked merged here, so no later
# sign-in or claim token can absorb it again. No backfill: guests before this
# were deleted or never claimed.
class AddMergedIntoToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :merged_into, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
  end
end
