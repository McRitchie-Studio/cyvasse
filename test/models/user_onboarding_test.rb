require "test_helper"

# [unit] User::Onboarding: which steps an account is missing, when the flow
# opens itself, the username suggestion, the legacy stats and the funnel.
class UserOnboardingTest < ActiveSupport::TestCase
  include LiveResults

  # Nameless, as LegacyImport writes a player: slug "user-<id>", username as
  # it was, whatever today's rules say.
  def legacy(username: "old_timer", **attrs)
    nameless("#{username.downcase.gsub(/\W/, "")}@example.com", legacy_id: 5000 + User.count, **attrs)
      .tap { |user| user.update_columns(username:) }
  end

  def nameless(email, **attrs)
    User.create!(email:, name: "Temp #{SecureRandom.hex(4)}", **attrs).tap { |user| user.update_columns(name: nil, slug: "user-#{user.id}") }
  end

  test "a legacy player misses every step and is due" do
    user = legacy
    assert_equal %w[welcome username profile contact], user.onboarding_missing
    assert user.onboarding_due?
  end

  test "a complete ordinary player misses only the optional steps and is not due" do
    user = player("arya")
    assert_equal %w[profile contact], user.onboarding_missing
    assert_not user.onboarding_due?
  end

  test "no name, or no usable username, makes an ordinary account due" do
    assert nameless("new@example.com").onboarding_due?
    assert User.create!(email: "named@example.com", name: "Named").onboarding_due?, "no username"
    assert_not player("bran", piece_skin: "vector", email_updates: true).onboarding_due?
    assert_empty player("rickon", piece_skin: "vector", email_updates: false).onboarding_missing
  end

  test "guests and computers are never due" do
    assert_not User.create_guest!.onboarding_due?
    assert_not User.create!(legacy_id: 3, username: "qavo_bot").onboarding_due?
  end

  test "a finished or skipped step is settled" do
    user = legacy
    user.record_onboarding!("welcome", "done")
    user.record_onboarding!("profile", "skipped")
    assert_equal %w[username contact], user.onboarding_missing
  end

  test "an unplayable username stays missing even when skipped" do
    user = legacy(username: "old timer!")
    user.record_onboarding!("username", "skipped")
    assert_includes user.onboarding_missing, "username"
    user.update!(username: "old_timer")
    assert_not_includes user.onboarding_missing, "username"
  end

  test "a legacy player confirms even a playable name once" do
    user = legacy(username: "fine_name")
    assert_includes user.onboarding_missing, "username"
    user.record_onboarding!("username", "done")
    assert_not_includes user.onboarding_missing, "username"
  end

  test "shown never overwrites a settled step" do
    user = legacy
    user.record_onboarding!("welcome", "done")
    user.record_onboarding!("welcome", "shown")
    assert_equal "done", user.reload.onboarding_status("welcome")
  end

  test "the flow has no welcome for a player who never played the old game" do
    assert_equal %w[username profile contact], player("arya").onboarding_flow
    assert_equal User::Onboarding::STEPS, legacy.onboarding_flow
  end

  test "suggests a free name that passes today's rules" do
    assert_equal "old_timer", legacy(username: " old timer! ").suggested_username
    player("taken_name")
    assert_equal "Taken_Name_2", legacy(username: "Taken Name").suggested_username
    assert_equal "a_very_long_lega", legacy(username: "a very long legacy name indeed").suggested_username
    assert_equal "player", nameless("x@example.com").tap { |u| u.update_columns(username: "!!") }.suggested_username
  end

  test "suggests from the email when there is no username" do
    assert_equal "jon_snow", nameless("jon.snow@example.com").suggested_username
  end

  test "legacy stats count imported matches and lineups, and skip never-started ones" do
    user = legacy
    rival = legacy(username: "rival")
    Match.create!(home_user: user, away_user: rival, winner: user, legacy_id: 1, match_status: Match::FINISHED, finish_reason: "king",
                  created_at: Time.zone.parse("2015-02-01"))
    Match.create!(home_user: rival, away_user: user, winner: rival, legacy_id: 2, match_status: Match::FINISHED, finish_reason: "king")
    Match.create!(home_user: user, away_user: rival, legacy_id: 3, match_status: Match::FINISHED, finish_reason: "expired",
                  created_at: Time.zone.parse("2014-01-01"))
    live_result(user, rival, winner: user) # a new-app game, not a legacy one
    Setup.new(user:, button_position: 1, units_position: "1:60|", name: "Old").save!(validate: false)

    stats = user.legacy_stats
    assert_equal({ played: 2, wins: 1, first_game_on: Date.new(2015, 2, 1), lineups: 1 }, stats)
  end

  test "legacy stats cost two queries however long the history" do
    user = legacy
    rival = legacy(username: "rival")
    30.times { |i| Match.create!(home_user: user, away_user: rival, winner: user, legacy_id: 100 + i, match_status: Match::FINISHED, finish_reason: "king") }
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { user.legacy_stats }
    assert_equal 2, queries.size, queries.join("\n")
  end

  test "the funnel counts each step's players by status" do
    a = legacy(username: "aaa")
    b = legacy(username: "bbb")
    a.record_onboarding!("welcome", "done")
    b.record_onboarding!("welcome", "shown")
    a.record_onboarding!("profile", "skipped")

    funnel = User.onboarding_funnel
    assert_equal({ "shown" => 1, "done" => 1, "skipped" => 0, "reached" => 2 }, funnel["welcome"])
    assert_equal({ "shown" => 0, "done" => 0, "skipped" => 1, "reached" => 1 }, funnel["profile"])
    assert_equal 0, funnel["contact"]["reached"]
  end
end
