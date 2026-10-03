# Usernames are unique in any case at the database, not only in
# User#username_free_in_any_case: two concurrent saves ("Arya" and "arya")
# both pass the validation, so only a unique index stops the second
# (task cyvasse-username-unique-index). NULL usernames stay allowed (Postgres
# never treats two NULLs as equal).
#
# Built CONCURRENTLY, so users stays writable while it builds. The new index
# is built before the old non-unique one is dropped, so lower(username)
# lookups are never without an index.
#
# It rewrites no data. While any two usernames differ only in case it refuses
# with the groups named, before building anything: on Heroku the release
# phase fails and the deploy does not go out. Resolve the names by hand
# (production held none on 2026-10-01), then deploy again.
class MakeLowerUsernameIndexUnique < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  OLD_INDEX = "index_users_on_lower_username".freeze
  NEW_INDEX = "index_users_on_lower_username_unique".freeze

  class CaseDuplicateUsernames < StandardError; end

  def up
    refuse_while_case_duplicates!

    # A concurrent build that failed part-way leaves an INVALID index behind
    # under the new name; this migration was not recorded, so drop it first.
    remove_index :users, name: NEW_INDEX, algorithm: :concurrently, if_exists: true
    add_index :users, "lower(username)", name: NEW_INDEX, unique: true, algorithm: :concurrently
    remove_index :users, name: OLD_INDEX, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :users, "lower(username)", name: OLD_INDEX, algorithm: :concurrently, if_not_exists: true
    remove_index :users, name: NEW_INDEX, algorithm: :concurrently, if_exists: true
  end

  # Each lower(username) held by more than one account, with its accounts.
  def case_duplicate_groups
    select_rows(<<~SQL)
      SELECT lower(username), string_agg(id::text || ':' || username, ', ' ORDER BY id)
      FROM users
      WHERE username IS NOT NULL
      GROUP BY lower(username)
      HAVING count(*) > 1
      ORDER BY lower(username)
    SQL
  end

  def refuse_while_case_duplicates!
    groups = case_duplicate_groups
    return if groups.empty?

    raise CaseDuplicateUsernames, <<~MSG.squish
      #{groups.size} username(s) are held by more than one account in different
      case, so a unique lower(username) index cannot be built. Rename all but
      one account in each group (id:username), then migrate again:
      #{groups.map { |name, accounts| "#{name} => #{accounts}" }.join("; ")}
    MSG
  end
end
