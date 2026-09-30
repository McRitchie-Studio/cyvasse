require "test_helper"

# [unit] Public usernames: the format, uniqueness in any case, lookup, and
# tolerance for legacy names that predate the rules, and reserved names.
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

  # task cyvasse-profile-username-edit: the reserved names, one rule for
  # onboarding, /username and the profile's Username card.
  test "a staff word is reserved in any case" do
    player = user("a@example.com")
    %w[admin ADMIN Moderator cyvasse Support].each do |name|
      assert_not player.update(username: name), name
      assert_includes player.errors[:username], "is reserved"
    end
    assert player.update(username: "admin_fan"), "only the exact word is reserved"
  end

  test "a guest's name is for guests being made, never picked" do
    player = user("a@example.com")
    assert_not player.update(username: "guest_4821")
    assert_includes player.errors[:username], "is reserved"

    guest = User.create_guest!(rng: Random.new(3))
    assert_match User::GUEST_USERNAME, guest.username
    assert_not guest.update(username: "Guest_1111"), "a guest cannot swap to another guest name"
    assert guest.update(username: "real_name"), "a guest can pick a real name"
  end

  test "a legacy player holding a reserved name keeps it" do
    legacy = user("legacy@example.com")
    legacy.update_column(:username, "admin")

    assert legacy.update(name: "Renamed", username: "admin"), "an unchanged reserved name is not re-checked"
  end

  test "the onboarding suggestion is never a reserved name" do
    admin = User.create!(email: "admin@example.com", name: "Ad")
    assert_equal "admin_2", admin.suggested_username

    guest = User.create_guest!(rng: Random.new(5))
    assert_not User.username_reserved?(guest.suggested_username)
  end

  test "players start with a clean record" do
    assert_equal [ 0, 0 ], [ user("a@example.com").wins, User.last.losses ]
  end
end
