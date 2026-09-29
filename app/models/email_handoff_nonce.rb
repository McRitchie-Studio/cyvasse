# A spent handoff assertion id (EmailHandoff), kept until the assertion would
# have expired. The unique index on jti is the lock: two dynos racing the same
# assertion both insert, and only one row lands.
class EmailHandoffNonce < ApplicationRecord
  # About one call in PRUNE_EVERY also deletes the expired rows.
  PRUNE_EVERY = 20

  # True when this call spent the jti; false when it was already spent.
  def self.claim!(jti, expires_at:, rng: Random)
    prune! if rng.rand(PRUNE_EVERY).zero?
    inserted = insert({ jti:, expires_at:, created_at: Time.current }, unique_by: :jti, returning: :id)
    inserted.rows.any?
  end

  def self.prune!(now: Time.current)
    where(expires_at: ...now).delete_all
  end
end
