# One request to /auth/email_handoff and how it ended, for the admin table
# (Admin::SignInsController). Holds no email and no assertion.
#
#   signed_in   an account was found and signed in
#   no_account  a good assertion for an address with no account
#   rejected    refused; `reason` is an EmailHandoff::Verifier reason, or
#               "rate_limited"
class EmailHandoffAttempt < ApplicationRecord
  OUTCOMES = %w[signed_in no_account rejected].freeze

  belongs_to :user, optional: true

  validates :outcome, inclusion: { in: OUTCOMES }

  # [{ outcome:, reason:, count:, last_at: }], most frequent first: one query.
  def self.summary
    group(:outcome, :reason).order(Arel.sql("COUNT(*) DESC"))
      .pluck(:outcome, :reason, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
      .map { |outcome, reason, count, last_at| { outcome:, reason:, count:, last_at: } }
  end

  def self.record(outcome, reason: nil, user: nil)
    create!(outcome:, reason: reason&.to_s, user:)
  end
end
