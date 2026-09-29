require "test_helper"

# [unit] EmailHandoff::Verifier: every line of the hub contract, and the jti
# replay store it spends into.
class EmailHandoff::VerifierTest < ActiveSupport::TestCase
  include HubAssertions

  def verify(assertion, key: hub_public_key)
    EmailHandoff::Verifier.new(key:).call(assertion)
  end

  test "a good assertion passes with the email and the ref" do
    token = hub_assertion("arya@example.com", ref: "hub-delivery-token-0001")
    result = verify(token)
    assert result.ok?
    assert_equal [ "arya@example.com", "hub-delivery-token-0001" ], [ result.email, result.ref ]
  end

  test "the same assertion twice is a replay" do
    token = hub_assertion
    assert verify(token).ok?
    assert_equal :replayed, verify(token).reason
  end

  test "the spent jti is kept until the assertion would have expired, plus the skew" do
    now = Time.current
    verify(hub_assertion(jti: "jti-kept-until-expiry-1", exp: now.to_i + 200, now:))
    nonce = EmailHandoffNonce.find_by!(jti: "jti-kept-until-expiry-1")
    assert_in_delta now.to_i + 200 + EmailHandoff::SKEW, nonce.expires_at.to_i, 1
  end

  {
    "a wrong issuer" => [ { iss: "evil.example" }, :wrong_issuer ],
    "a wrong audience" => [ { aud: "turf-monster" }, :wrong_audience ],
    "an expired assertion" => [ { iat: 10.minutes.ago.to_i, exp: 6.minutes.ago.to_i }, :expired ],
    "one issued in the future past the skew" => [ { iat: 2.minutes.from_now.to_i, exp: 4.minutes.from_now.to_i }, :issued_in_future ],
    "a lifetime over five minutes" => [ { iat: 10.seconds.ago.to_i, exp: 291.seconds.from_now.to_i }, :lifetime_too_long ],
    "no jti" => [ { jti: nil }, :missing_claim ],
    "no ref" => [ { ref: nil }, :missing_claim ],
    "no sub" => [ { sub: nil }, :missing_claim ],
    "a sub not lowercased" => [ { sub: "Arya@Example.com" }, :bad_subject ],
    "a sub that is no email" => [ { sub: "arya" }, :bad_subject ],
    "a short jti" => [ { jti: "abc" }, :bad_jti ],
    "a ref that is no delivery token" => [ { ref: "x" }, :bad_ref ]
  }.each do |label, (claims, reason)|
    test "refuses #{label}" do
      result = verify(hub_assertion("arya@example.com", **claims))
      assert_not result.ok?
      assert_equal reason, result.reason
      assert_nil result.email
    end
  end

  test "allows up to thirty seconds of clock skew" do
    assert verify(hub_assertion(iat: 25.seconds.from_now.to_i, exp: 2.minutes.from_now.to_i)).ok?
    assert verify(hub_assertion(iat: 3.minutes.ago.to_i, exp: 20.seconds.ago.to_i)).ok?
    assert_equal :expired, verify(hub_assertion(iat: 3.minutes.ago.to_i, exp: 40.seconds.ago.to_i)).reason
  end

  test "exactly five minutes is allowed" do
    assert verify(hub_assertion(exp: 300.seconds.from_now.to_i)).ok?
  end

  test "refuses a signature from another key" do
    assert_equal :bad_signature, verify(hub_assertion(key: OTHER_KEY)).reason
  end

  test "refuses alg none" do
    token = JWT.encode(hub_claims("arya@example.com"), nil, "none")
    assert_equal :bad_algorithm, verify(token).reason
  end

  test "refuses an HMAC assertion keyed with the public key" do
    token = JWT.encode(hub_claims("arya@example.com"), hub_public_pem, "HS256")
    assert_equal :bad_algorithm, verify(token).reason
  end

  test "refuses ES384 even from a key of the right family" do
    token = JWT.encode(hub_claims("arya@example.com"), OpenSSL::PKey::EC.generate("secp384r1"), "ES384")
    assert_equal :bad_algorithm, verify(token).reason
  end

  test "refuses garbage and a blank assertion" do
    assert_equal :malformed, verify("not.a.jwt").reason
    assert_equal :missing, verify("").reason
    assert_equal :missing, verify(nil).reason
  end

  test "a refused assertion spends no jti" do
    verify(hub_assertion(aud: "elsewhere", jti: "jti-that-was-refused-01"))
    assert_not EmailHandoffNonce.exists?(jti: "jti-that-was-refused-01")
  end

  test "reads the key from MS_HANDOFF_PUBLIC_KEY, with literal newlines too" do
    token = hub_assertion
    with_hub_key(hub_public_pem.gsub("\n", "\\n")) { assert EmailHandoff::Verifier.new.call(token).ok? }
  end

  test "without a key it fails closed" do
    with_hub_key(nil) { assert_equal :not_configured, EmailHandoff::Verifier.new.call(hub_assertion).reason }
    with_hub_key("not a pem") { assert_equal :not_configured, EmailHandoff::Verifier.new.call(hub_assertion).reason }
  end

  test "a private key in the config var is refused" do
    with_hub_key(HUB_KEY.to_pem) { assert_equal :not_configured, EmailHandoff::Verifier.new.call(hub_assertion).reason }
  end
end
