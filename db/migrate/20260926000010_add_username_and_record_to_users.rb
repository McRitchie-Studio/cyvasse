# Public usernames and the win/loss record for online matches (epic
# cyvasse-revival piece 6). Named and typed as the legacy users table had them
# (amcritchie/Cyvasse db/schema.rb: username string, wins/losses integer), so
# piece 10 can import the 18,789 legacy players column for column.
#
# The unique index is on the exact spelling, as the legacy uniqueness was
# (Rails 4's validates_uniqueness_of is case-sensitive), so legacy rows that
# differ only in case still import; the model refuses a new name that
# collides with any existing one in any case, and finds names through the
# lower(username) index.
class AddUsernameAndRecordToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :username, :string
    add_column :users, :wins, :integer, default: 0, null: false
    add_column :users, :losses, :integer, default: 0, null: false
    add_index :users, :username, unique: true
    add_index :users, "lower(username)", name: "index_users_on_lower_username"
  end
end
