# Checks one hub assertion against the contract in EmailHandoff, and spends
# its jti. Returns a Result: ok with the email and ref, or the reason it was
# refused. Never raises for a bad assertion; raises NotConfigured only through
# the result (reason :not_configured), so the caller can fail closed.
#
#   EmailHandoff::Verifier.new.call(assertion)  # => Result
module EmailHandoff
  class Verifier
    Result = Data.define(:reason, :email, :ref) do
      def ok? = reason.nil?
    end

    # Every reason a Result can carry, for the admin table.
    REASONS = %i[missing not_configured malformed bad_algorithm bad_signature wrong_issuer wrong_audience
                 expired issued_in_future lifetime_too_long missing_claim bad_subject bad_jti bad_ref replayed].freeze

    REQUIRED = %w[iss aud sub jti iat exp ref].freeze

    # key: an OpenSSL EC public key; by default the one in MS_HANDOFF_PUBLIC_KEY.
    def initialize(key: :from_env)
      @key = key
    end

    def call(assertion)
      return refuse(:missing) if assertion.blank?

      key = @key == :from_env ? EmailHandoff.public_key : @key
      return refuse(:not_configured) unless key

      claims = decode(assertion.to_s, key)
      return claims if claims.is_a?(Result)

      reason = claim_problem(claims)
      return refuse(reason) if reason
      return refuse(:replayed) unless EmailHandoffNonce.claim!(claims["jti"], expires_at: Time.zone.at(claims["exp"]) + SKEW)

      Result.new(reason: nil, email: claims["sub"], ref: claims["ref"])
    rescue NotConfigured
      refuse(:not_configured)
    end

    private

    # The signature, the algorithm, iss, aud, exp and iat, by the jwt gem.
    # ES256 is pinned: the header's alg is never trusted, and "none" or an
    # HMAC alg keyed with the public key are refused before any check.
    def decode(assertion, key)
      JWT.decode(assertion, key, true,
                 algorithm: ALGORITHM,
                 iss: ISSUER, verify_iss: true,
                 aud: AUDIENCE, verify_aud: true,
                 verify_expiration: true, leeway: SKEW,
                 verify_iat: { leeway: SKEW },
                 required_claims: REQUIRED).first
    rescue JWT::IncorrectAlgorithm then refuse(:bad_algorithm)
    rescue JWT::VerificationError then refuse(:bad_signature)
    rescue JWT::InvalidIssuerError then refuse(:wrong_issuer)
    rescue JWT::InvalidAudError then refuse(:wrong_audience)
    rescue JWT::ExpiredSignature then refuse(:expired)
    rescue JWT::InvalidIatError then refuse(:issued_in_future)
    rescue JWT::MissingRequiredClaim then refuse(:missing_claim)
    rescue JWT::DecodeError then refuse(:malformed)
    end

    def claim_problem(claims)
      iat = claims["iat"]
      exp = claims["exp"]
      return :malformed unless iat.is_a?(Numeric) && exp.is_a?(Numeric)
      return :lifetime_too_long if exp - iat > MAX_LIFETIME || exp <= iat

      sub = claims["sub"]
      return :bad_subject unless sub.is_a?(String) && sub == sub.strip.downcase && sub.match?(URI::MailTo::EMAIL_REGEXP)
      return :bad_jti unless claims["jti"].is_a?(String) && claims["jti"].match?(JTI)
      return :bad_ref unless claims["ref"].is_a?(String) && claims["ref"].match?(EmailReferral::TOKEN)

      nil
    end

    def refuse(reason)
      Result.new(reason:, email: nil, ref: nil)
    end
  end
end
