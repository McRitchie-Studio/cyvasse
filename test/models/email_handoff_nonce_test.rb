require "test_helper"

# [unit] The replay store: insert-or-fail on a unique jti, pruned as it goes.
class EmailHandoffNonceTest < ActiveSupport::TestCase
  NEVER_PRUNE = Struct.new(:value) { def rand(_) = value }

  test "a jti is claimed once" do
    assert EmailHandoffNonce.claim!("jti-claimed-once-000001", expires_at: 5.minutes.from_now, rng: NEVER_PRUNE.new(1))
    assert_not EmailHandoffNonce.claim!("jti-claimed-once-000001", expires_at: 5.minutes.from_now, rng: NEVER_PRUNE.new(1))
    assert_equal 1, EmailHandoffNonce.where(jti: "jti-claimed-once-000001").count
  end

  test "the unique index is the lock, not a lookup" do
    EmailHandoffNonce.create!(jti: "jti-already-in-the-table", expires_at: 1.minute.from_now)
    assert_not EmailHandoffNonce.claim!("jti-already-in-the-table", expires_at: 5.minutes.from_now, rng: NEVER_PRUNE.new(1))
  end

  test "prune deletes only expired rows" do
    EmailHandoffNonce.create!(jti: "jti-expired-row-0000001", expires_at: 1.second.ago)
    EmailHandoffNonce.create!(jti: "jti-live-row-000000001", expires_at: 1.minute.from_now)
    assert_equal 1, EmailHandoffNonce.prune!
    assert_equal [ "jti-live-row-000000001" ], EmailHandoffNonce.pluck(:jti)
  end

  test "claiming prunes now and then" do
    EmailHandoffNonce.create!(jti: "jti-expired-row-0000002", expires_at: 1.second.ago)
    EmailHandoffNonce.claim!("jti-new-claim-00000001", expires_at: 5.minutes.from_now, rng: NEVER_PRUNE.new(0))
    assert_not EmailHandoffNonce.exists?(jti: "jti-expired-row-0000002")
  end
end
