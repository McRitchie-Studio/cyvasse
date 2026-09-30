# /sitemap.xml: the public pages SeoPage names, each with its canonical URL
# and <lastmod> (task cyvasse-seo-profile). Built per request, so the
# leaderboard's lastmod moves with the last finished game.
class SitemapsController < ApplicationController
  skip_before_action :require_authentication

  def show
    @pages = SeoPage.sitemap_pages
    expires_in 1.hour, public: true
    render formats: :xml
  end
end
