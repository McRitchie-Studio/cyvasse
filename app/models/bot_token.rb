# A bearer token for one computer player's remote runner (Tyrion's first):
# it lets that account play its own matches and write in their chats over
# /api/bot (Api::Bot), and nothing a signed-in player could not already do
# from a browser. Only the SHA-256 digest is stored; the token itself is shown
# once, when issued (`bin/rails "bot_tokens:issue[tyrion]"`), and a leaked one
# is revoked the same way (`bot_tokens:revoke[id]`).
#
# Only computer players (User#computer?) may hold one, so a token can never
# stand in for a person's account.
class BotToken < ApplicationRecord
  PREFIX = "cyb_"
  # last_used_at is the runner's heartbeat; it is written at most this often.
  TOUCH_EVERY = 10.seconds

  belongs_to :user

  scope :active, -> { where(revoked_at: nil) }

  validates :token_digest, presence: true, uniqueness: true
  validate :held_by_a_computer_player

  # Returns [record, token]. The token is not recoverable afterwards.
  def self.issue!(user, name: nil)
    token = PREFIX + SecureRandom.base58(40)
    [ create!(user:, name:, token_digest: digest(token)), token ]
  end

  # The active token for `token`, or nil. A token whose account is no longer
  # a computer player is refused too.
  def self.authenticate(token)
    return nil if token.blank?

    found = active.includes(:user).find_by(token_digest: digest(token))
    found if found&.user&.computer?
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

  # Has any runner for `user` been heard from within `within`?
  def self.heard_from?(user, within: 1.minute, now: Time.current)
    active.where(user:).where(last_used_at: (now - within)..).exists?
  end

  def revoke!(now = Time.current)
    update!(revoked_at: now) unless revoked_at
  end

  def revoked? = revoked_at.present?

  def heard!(now = Time.current)
    update_column(:last_used_at, now) if last_used_at.nil? || last_used_at < now - TOUCH_EVERY
  end

  private

  def held_by_a_computer_player
    errors.add(:user, "must be a computer player") unless user&.computer?
  end
end
