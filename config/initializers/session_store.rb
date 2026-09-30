# The session cookie, and the one switch that joins Cyvasse to the hub's SSO.
#
# Hub SSO in studio-engine rides the SESSION, not a token: when a player signs
# in on mcritchie.studio the hub writes sso_* fields into its session, and a
# satellite that can read that same cookie offers "Continue as ..." on its
# sign-in page (the engine's POST /sso_continue). Reading it takes three
# things together: the hub's cookie KEY, its DOMAIN (.mcritchie.studio), and
# the hub's SECRET_KEY_BASE, because the cookie is encrypted with it.
#
# So the shared cookie is OPT-IN, via STUDIO_SSO_SHARED_COOKIE=true, and off by
# default. Flipping the key and domain WITHOUT the hub's secret is worse than no
# SSO: both apps would write one cookie neither can decrypt, signing players
# out of the hub on every visit here. NEW_APP_SETUP section 4 says the same:
# app-specific key by default, shared-domain SSO only once the hub/satellite
# cookie contract is reviewed. Hosting (epic piece 8) sets the secret and the
# flag together.
#
# The shared cookie can only ever reach the old cyvasse.mcritchie.studio host.
# Cyvasse lives on www.cyvasse.xyz now (lib/cyvasse/canonical_host.rb), a
# different site the hub's cookie cannot reach, so hub SSO does not work there
# whatever the flag says; there the cookie falls back to the request host.
#
# Off the flag the cookie is Cyvasse's own. On a developer desk its key is
# overridable (CYVASSE_SESSION_KEY) so two stacks on localhost do not trample
# each other's session, the collision turf-monster hit with TM_SESSION_KEY.
module CyvasseSessionCookie
  APP_KEY = "_cyvasse_session".freeze
  HUB_KEY = "_studio_session".freeze
  HUB_DOMAIN = ".mcritchie.studio".freeze

  def self.shared?(env)
    env["STUDIO_SSO_SHARED_COOKIE"].to_s.strip.downcase == "true"
  end

  def self.options(production:, env: ENV)
    base = { secure: production, httponly: true, same_site: :lax }

    if production && shared?(env)
      # A list, not a string: Rails scopes the cookie to the entry the request
      # host ends with, and leaves it host-only when none matches. A bare
      # string would send Domain=.mcritchie.studio from www.cyvasse.xyz, which
      # the browser rejects, and no one could stay signed in there.
      base.merge(key: HUB_KEY, domain: [ HUB_DOMAIN ])
    elsif production
      base.merge(key: APP_KEY)
    else
      base.merge(key: env.fetch("CYVASSE_SESSION_KEY", APP_KEY))
    end
  end
end

Rails.application.config.session_store :cookie_store,
  **CyvasseSessionCookie.options(production: Rails.env.production?)
