# Assertions signed as the hub signs them (EmailHandoff), with a P-256 key
# pair generated for this test run: the private half never leaves the tests.
module HubAssertions
  HUB_KEY = OpenSSL::PKey::EC.generate("prime256v1")
  OTHER_KEY = OpenSSL::PKey::EC.generate("prime256v1")

  def hub_public_pem(key = HUB_KEY)
    key.public_to_pem
  end

  def hub_public_key
    OpenSSL::PKey::EC.new(hub_public_pem)
  end

  def hub_claims(email, now: Time.current, **overrides)
    { "iss" => "mcritchie.studio", "aud" => "cyvasse", "sub" => email, "jti" => SecureRandom.hex(16),
      "iat" => now.to_i, "exp" => now.to_i + 120, "ref" => "delivery-token-#{SecureRandom.hex(8)}" }
      .merge(overrides.transform_keys(&:to_s)).compact
  end

  def hub_assertion(email = "arya@example.com", key: HUB_KEY, alg: "ES256", **claims)
    JWT.encode(hub_claims(email, **claims), key, alg)
  end

  # Sets MS_HANDOFF_PUBLIC_KEY (nil removes it) for the block.
  def with_hub_key(pem = hub_public_pem)
    previous = ENV[EmailHandoff::KEY_ENV]
    ENV[EmailHandoff::KEY_ENV] = pem
    yield
  ensure
    ENV[EmailHandoff::KEY_ENV] = previous
  end
end
