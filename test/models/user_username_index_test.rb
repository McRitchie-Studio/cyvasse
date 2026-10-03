require "test_helper"
require Rails.root.join("db/migrate/20261001000000_make_lower_username_index_unique")

# [unit] Usernames are unique in any case at the database (task
# cyvasse-username-unique-index): two saves that both pass the validation
# cannot both take "Arya" and "arya"; the loser fails as the validation would
# have, and the migration that builds the index refuses while names collide.
class UserUsernameIndexTest < ActiveSupport::TestCase
  include UsernameRace

  def user(email, username: nil)
    User.create!(email:, name: email.split("@").first, username:)
  end

  test "the lower(username) index is unique" do
    index = User.connection.indexes(:users).find { |i| i.name == "index_users_on_lower_username_unique" }
    assert index, "the unique index exists"
    assert index.unique
    assert_not User.connection.index_name_exists?(:users, "index_users_on_lower_username"), "the old index is gone"
  end

  test "a case variant saved past the validation fails as taken" do
    user("a@example.com", username: "Arya")
    other = user("b@example.com")

    other.username = "arya"
    assert_not other.save(validate: false), "the index stops the second name"
    assert_equal [ "is taken" ], other.errors[:username]
    assert_nil other.reload.username
  end

  test "the race fails as taken through update, and update! raises RecordInvalid" do
    user("a@example.com", username: "Arya")
    other = user("b@example.com")

    as_if_the_check_raced do
      assert_not other.update(username: "ARYA")
      assert_includes other.errors[:username], "is taken"
      error = assert_raises(ActiveRecord::RecordInvalid) { other.update!(username: "aRyA") }
      assert_includes error.record.errors[:username], "is taken"
    end
    assert_nil other.reload.username
  end

  test "a new account created past the validation fails as taken" do
    user("a@example.com", username: "Arya")

    as_if_the_check_raced do
      late = User.new(email: "b@example.com", name: "b", username: "arya")
      assert_not late.save
      assert_includes late.errors[:username], "is taken"
      assert late.new_record?
    end
    assert_equal 1, User.where("lower(username) = 'arya'").count
  end

  test "the exact-case index fails as taken too" do
    user("a@example.com", username: "Arya")
    other = user("b@example.com")
    other.username = "Arya"

    assert_not other.save(validate: false)
    assert_includes other.errors[:username], "is taken"
  end

  test "a caller's transaction stays usable after losing the race" do
    user("a@example.com", username: "Arya")
    other = user("b@example.com")

    User.transaction do
      as_if_the_check_raced { assert_not other.update(username: "arya") }
      assert other.reload.update!(name: "Still Writable"), "the outer transaction still takes writes"
    end
    assert_equal "Still Writable", other.reload.name
  end

  test "another unique violation still raises" do
    user("a@example.com")
    other = user("b@example.com")
    other.email = "a@example.com"

    assert_raises(ActiveRecord::RecordNotUnique) { other.save(validate: false) }
  end

  test "any number of accounts may have no username" do
    3.times { |n| user("none#{n}@example.com") }
    assert_equal 3, User.where(username: nil, email: %w[none0@example.com none1@example.com none2@example.com]).count
  end

  test "the migration refuses while two usernames differ only in case" do
    user("a@example.com", username: "Arya")
    other = user("b@example.com")
    migration = MakeLowerUsernameIndexUnique.new
    migration.verbose = false

    assert_nil migration.refuse_while_case_duplicates!, "no collision, no refusal"

    # The state the index forbids: drop it inside the test's transaction (DDL
    # in Postgres rolls back with it), then let a case variant in.
    User.connection.remove_index(:users, name: "index_users_on_lower_username_unique")
    other.update_column(:username, "ARYA")

    error = assert_raises(MakeLowerUsernameIndexUnique::CaseDuplicateUsernames) { migration.refuse_while_case_duplicates! }
    assert_match "arya => #{User.find_by!(email: 'a@example.com').id}:Arya, #{other.id}:ARYA", error.message
    assert_raises(MakeLowerUsernameIndexUnique::CaseDuplicateUsernames) { migration.up }
    assert_not User.connection.index_name_exists?(:users, "index_users_on_lower_username_unique"), "it built nothing"
  end
end
