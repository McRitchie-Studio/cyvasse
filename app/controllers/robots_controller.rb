# /robots.txt (task cyvasse-seo-profile), replacing the Rails default in
# public/. Rendered rather than static so the Sitemap line is an absolute URL
# on the canonical host (Cyvasse.canonical_url).
#
# Public pages are allowed; the paths behind a sign-in, the admin, the bot
# API, the sign-in and onboarding flows and the match and live-seek pages are
# disallowed. Those pages also carry <meta name="robots" content="noindex">
# (SeoHelper), but a crawler that obeys the Disallow never fetches them, so it
# never reads that tag: robots.txt stops the crawl, and a URL Google already
# knows can stay listed as a bare link. To drop one from the index, lift its
# Disallow so Googlebot can read the noindex, or remove it in Search Console.
class RobotsController < ApplicationController
  skip_before_action :require_authentication

  DISALLOW = %w[
    /admin
    /api/
    /matches
    /live/
    /inbox
    /conversations
    /onboarding
    /username
    /profile
    /skin
    /models/
    /lineups
    /signin
    /signup
    /login
    /logout
    /magic_link
    /l/
    /sso_login
    /sso_continue
    /auth/
    /account/
    /leaderboard/join
    /error_logs
    /_studio/
    /cable
  ].freeze

  def show
    expires_in 1.day, public: true
    render plain: body_text, content_type: "text/plain"
  end

  private

  def body_text
    lines = [ "User-agent: *", "Allow: /" ]
    lines += DISALLOW.map { |path| "Disallow: #{path}" }
    lines << ""
    lines << "Sitemap: #{helpers.seo_absolute_url('/sitemap.xml')}"
    "#{lines.join("\n")}\n"
  end
end
