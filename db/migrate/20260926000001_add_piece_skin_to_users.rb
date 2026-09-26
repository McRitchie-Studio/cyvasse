# The piece art a signed-in player chose (epic cyvasse-revival piece 5).
# Nullable: nil means "never chose", and the cookie or the vector default
# answers instead.
class AddPieceSkinToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :piece_skin, :string
  end
end
