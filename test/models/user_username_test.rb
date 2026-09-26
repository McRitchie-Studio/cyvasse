require "test_helper"

# [unit] Public usernames: the format, uniqueness in any case, lookup, and
# tolerance for legacy names that predate the rules.
class UserUsernameTest < ActiveSupport::TestCase
  def user(email, username: nil)
    User.create!(email:, name: email.split("@").first, username:)
  end

  test "a username is 3 to 20 letters, digits or underscores" do
    player = user("a@example.com")
    %w[ab has\ space way_too_long_for_a_username dot.ted].each do |bad|
      assert_not player.update(username: bad), bad
    end
    assert player.update(username: "Snow_99")
  end

  test "a username is unique in any case, and found in any case" do
    user("a@example.com", username: "Jon")
    other = user("b@example.com")

    assert_not other.update(username: "jON")
    assert_includes other.errors[:username], "is taken"
    assert_equal "a@example.com", User.find_by_username(" jon ").email
    assert_nil User.find_by_username(nil)
  end

  test "a legacy name outside today's format still saves other changes" do
    legacy = user("legacy@example.com")
    legacy.update_column(:username, "old name!")

    assert legacy.update(name: "Renamed"), "only a changed username is re-checked"
  end

  test "players start with a clean record" do
    assert_equal [ 0, 0 ], [ user("a@example.com").wins, User.last.losses ]
  end
end
