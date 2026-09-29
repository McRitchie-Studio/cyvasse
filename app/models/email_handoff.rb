# The email sign-in handoff (task cyvasse-legacy-onboarding-handoff). The hub
# (mcritchie.studio) sends the "Cyvasse is back" emails; a click on a CTA is
# proof the player holds that address, so the hub checks the click and
# redirects here with a short-lived assertion it signed:
#
#   GET /auth/email_handoff?assertion=<JWT>&return_to=<local path>
#
# The contract the hub signs to (EmailHandoff::Verifier checks every line):
#
#   header  alg ES256 (nothing else is accepted, "none" included)
#   iss     "mcritchie.studio"
#   aud     "cyvasse"
#   sub     the recipient's email, lowercased
#   jti     a nonce, 16-128 characters; each one signs in once
#   iat     issue time (unix seconds), no more than 30 s in the future
#   exp     expiry, after now (30 s skew allowed), and exp - iat <= 300
#   ref     the hub's delivery token (EmailReferral::TOKEN)
#
# The key is the hub's public key, a PEM in MS_HANDOFF_PUBLIC_KEY. Without it
# the endpoint fails closed: no session, and a NotConfigured error logged.
module EmailHandoff
  ISSUER = "mcritchie.studio"
  AUDIENCE = "cyvasse"
  ALGORITHM = "ES256"
  MAX_LIFETIME = 300 # seconds, exp - iat
  SKEW = 30 # seconds of clock drift allowed either way
  KEY_ENV = "MS_HANDOFF_PUBLIC_KEY"
  JTI = /\A[\w.:-]{16,128}\z/

  # The public key is missing or unreadable.
  class NotConfigured < StandardError; end

  # The session a handoff started. Play, chat and onboarding need nothing more;
  # a sensitive action needs a fresh magic link (ConfirmedSession).
  SESSION_KEY = :auth_method
  SESSION_VALUE = "email_handoff"

  # The hub's public key, or nil when MS_HANDOFF_PUBLIC_KEY is blank. Heroku
  # config often carries a PEM with literal "\n"; both spellings are read.
  def self.public_key(pem = ENV[KEY_ENV])
    return nil if pem.blank?

    key = OpenSSL::PKey::EC.new(pem.gsub("\\n", "\n"))
    raise NotConfigured, "#{KEY_ENV} is not a P-256 public key" unless key.group.curve_name == "prime256v1" && !key.private?

    key
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    raise NotConfigured, "#{KEY_ENV} is not a readable PEM"
  end
end
