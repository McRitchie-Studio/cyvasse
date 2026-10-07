require "test_helper"

# [unit] User#name_slug (Sluggable): every account gets a non-empty slug that
# no other account holds, whatever its name looks like, and an existing slug is
# never rewritten while the name it came from stands.
class UserSlugTest < ActiveSupport::TestCase
  def slugs_for(*names)
    names.map.with_index { |name, i| User.create!(email: "p#{i}-#{SecureRandom.hex(3)}@example.com", name:).slug }
  end

  def assert_valid_distinct(slugs)
    slugs.each { |slug| assert_match(/\A[a-z0-9][a-z0-9_-]*\z/, slug) }
    assert_equal slugs.size, slugs.uniq.size, "slugs must be distinct: #{slugs.inspect}"
  end

  test "two nameless accounts get distinct, non-empty slugs" do
    slugs = slugs_for(nil, nil, "", "   ")

    assert_valid_distinct slugs
    slugs.each { |slug| refute_equal "user-", slug }
  end

  test "emoji-only and non-Latin names fall back to a usable slug" do
    slugs = slugs_for("Иван", "Иван", "🐉🐉", "🐉", "李雷", "Ωmega")

    assert_valid_distinct slugs
    assert_equal "mega", slugs.last, "the Latin part survives"
  end

  test "Latin accents are transliterated" do
    assert_equal [ "jose-nunez" ], slugs_for("José Núñez")
  end

  test "a nameless account with a username slugs from the username" do
    user = User.create!(email: "u@example.com", username: "Old_Timer")

    assert_equal "old_timer", user.slug
  end

  test "a colliding name is suffixed rather than refused" do
    assert_equal %w[carl carl-2 carl-3], slugs_for("Carl", "carl", "CARL")
  end

  test "suffixing continues past the highest suffix in use" do
    User.create!(email: "x@example.com", name: "Someone").update_columns(slug: "carl-7")

    assert_equal %w[carl carl-8], slugs_for("Carl", "Carl")
  end

  test "a save that leaves the name alone never rewrites the slug" do
    legacy = User.create!(email: "legacy@example.com", name: "Temp", legacy_id: 4242)
    legacy.update_columns(name: nil, slug: "user-#{legacy.id}", username: "legacy_one")

    legacy.update!(username: "renamed_one", wins: 3)

    assert_equal "user-#{legacy.id}", legacy.reload.slug
  end

  test "a name change that keeps the same stem keeps the suffixed slug" do
    slugs_for("Carl")
    second = User.create!(email: "c2@example.com", name: "Carl")
    assert_equal "carl-2", second.slug

    second.update!(name: "CARL")

    assert_equal "carl-2", second.reload.slug
  end

  # studio-engine's Sluggable writes the slug once, at create, from the release
  # that ships rename_slug! (task slugs-set-once-then-cascade); before it, a
  # later name moved the slug. Both hold until the lock carries that release,
  # then only the first branch stays (task cyvasse-slug-test-both-engines).
  test "a name typed after signup moves the slug only on an engine that recomputes it" do
    user = User.create!(email: "c@example.com", name: nil)
    was = user.slug
    user.update!(name: "Rook Ravenholt")

    if Sluggable.method_defined?(:rename_slug!)
      assert_equal was, user.reload.slug, "the slug is written once, at create"
    else
      assert_equal "rook-ravenholt", user.reload.slug
    end
  end

  test "a lost race on the slug index retries with a fresh slug" do
    User.create!(email: "first@example.com", name: "Racer")
    user = User.new(email: "second@example.com", name: "Racer")
    # Simulate the race: the free-slug check misses the row a concurrent
    # insert just committed, so the INSERT hits the unique index.
    stale = true
    user.define_singleton_method(:slug_taken?) do |candidate|
      next super(candidate) unless stale

      stale = false
      false
    end

    User.transaction { user.save! }

    assert user.persisted?
    assert_equal "racer-2", user.slug
  end

  test "an unrelated unique violation is not swallowed by the slug retry" do
    User.create!(email: "dup@example.com", name: "One")

    assert_raises(ActiveRecord::RecordNotUnique) { User.create!(email: "dup@example.com", name: "Two") }
  end

  test "a unique violation quoting the slug index name in its value still raises" do
    User.create!(email: "index_users_on_slug@example.com", name: "One")
    inserts = 0
    counter = ->(*, payload) { inserts += 1 if payload[:sql].start_with?('INSERT INTO "users"') }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      assert_raises(ActiveRecord::RecordNotUnique) { User.create!(email: "index_users_on_slug@example.com", name: "Two") }
    end
    assert_equal 1, inserts, "an email violation is raised on the first try, never retried as a slug race"
  end
end
