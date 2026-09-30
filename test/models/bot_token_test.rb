require "test_helper"

# [unit] A remote runner's token: issued once, stored as a digest, held only
# by a computer player, and dead once revoked.
class BotTokenTest < ActiveSupport::TestCase
  setup do
    @tyrion = User.create!(legacy_id: 3, username: "tyrion", name: "Tyrion Lannister")
  end

  test "issue returns the token once and stores only its digest" do
    record, token = BotToken.issue!(@tyrion, name: "isolated box")
    assert token.start_with?(BotToken::PREFIX)
    assert_equal BotToken.digest(token), record.token_digest
    refute_includes BotToken.connection.select_all("SELECT * FROM bot_tokens").rows.flatten.map(&:to_s), token
  end

  test "authenticate finds the active token and nothing else" do
    record, token = BotToken.issue!(@tyrion)
    assert_equal record, BotToken.authenticate(token)
    assert_nil BotToken.authenticate("#{token}x")
    assert_nil BotToken.authenticate("")
    assert_nil BotToken.authenticate(nil)

    record.revoke!
    assert_nil BotToken.authenticate(token), "a revoked token is refused"
  end

  test "only a computer player may hold one" do
    person = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    error = assert_raises(ActiveRecord::RecordInvalid) { BotToken.issue!(person) }
    assert_match(/computer player/, error.message)
  end

  test "a token whose account stopped being a computer player is refused" do
    _record, token = BotToken.issue!(@tyrion)
    @tyrion.update_column(:legacy_id, 99)
    assert_nil BotToken.authenticate(token)
  end

  test "heard! is the heartbeat, written at most every ten seconds" do
    record, _token = BotToken.issue!(@tyrion)
    now = Time.current
    refute BotToken.heard_from?(@tyrion, now:)

    record.heard!(now)
    assert BotToken.heard_from?(@tyrion, now:)
    record.heard!(now + 5.seconds)
    assert_in_delta now, record.reload.last_used_at, 1
    record.heard!(now + 11.seconds)
    assert_in_delta now + 11.seconds, record.reload.last_used_at, 1

    refute BotToken.heard_from?(@tyrion, within: 1.minute, now: now + 2.minutes)
  end
end
