require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "slug derives from the name" do
    user = User.create!(email: "carl@example.com", name: "Carl Test")

    assert_equal "carl-test", user.slug
  end

  test "display_name falls back to the email's local part" do
    assert_equal "carl", User.new(email: "carl@example.com").display_name
    assert_equal "User", User.new.display_name
  end

  test "new users are viewers, not admins" do
    user = User.create!(email: "carl@example.com", name: "Carl Test")

    assert_equal "viewer", user.role
    refute user.admin?
  end

  test "avatar helpers answer for the engine nav" do
    user = User.new(email: "carl@example.com", name: "carl")

    assert_equal "C", user.avatar_initials
    assert_includes User::AVATAR_COLORS, user.avatar_color
  end

  test "seed identities: two admins and one member, idempotent" do
    first = User.seed_identities!
    second = User.seed_identities!

    assert_equal first.map(&:id), second.map(&:id), "re-seeding must not create duplicates"
    assert_equal 3, first.size
    assert_equal %w[alex@cyvasse.mcritchie.studio alex@mcritchie.studio], first.select(&:admin?).map(&:email).sort
    assert_equal [ "mack@mcritchie.studio" ], first.reject(&:admin?).map(&:email)
  end

  test "seed identities never overwrite an existing row" do
    User.create!(email: "mack@mcritchie.studio", name: "Mack Renamed", role: "viewer")

    User.seed_identities!

    assert_equal "Mack Renamed", User.find_by!(email: "mack@mcritchie.studio").name
  end

  test "piece_skin is nil until chosen, and only a real skin is accepted" do
    user = User.create!(email: "carl@example.com", name: "Carl Test")
    assert_nil user.piece_skin

    assert user.update(piece_skin: "pencil")
    assert user.update(piece_skin: "vector")
    refute user.update(piece_skin: "chalk")
    assert_includes user.errors[:piece_skin], "is not included in the list"
  end
end
