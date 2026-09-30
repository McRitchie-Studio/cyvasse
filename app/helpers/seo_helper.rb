# The head tags a search engine and a link preview read (task
# cyvasse-seo-profile): <title>, the meta description, the canonical link,
# robots, Open Graph, the Twitter card, JSON-LD and Search Console's
# verification tag. The copy lives in SeoPage; layouts/_seo renders the tags.
#
#   <% seo_page :rules %>                          a public, indexed page
#   <% seo_page :home, json_ld: [ ... ] %>         plus that page's structured data
#
# A page that never calls seo_page is noindex (see SeoPage).
#
# Every absolute URL is built on Cyvasse.canonical_url (the canonical-host
# task's single source), so production says https://www.cyvasse.xyz whatever
# host the request came in on. Where no canonical host is set (a desk, a
# test), the request's own origin stands in, so the tags still render whole.
module SeoHelper
  DEFAULT_OG_IMAGE = "og/default.png".freeze
  OG_IMAGE_WIDTH = 1200
  OG_IMAGE_HEIGHT = 630

  def seo_page(key, json_ld: [])
    @seo_page = SeoPage.find(key)
    @seo_json_ld = Array(json_ld)
    content_for(:title, @seo_page.title)
  end

  def current_seo_page = @seo_page

  def seo_indexable? = @seo_page.present?

  def seo_json_ld = @seo_json_ld || []

  # An absolute URL for a path on this site.
  def seo_absolute_url(path)
    Cyvasse.canonical_url(path) || "#{request.base_url}#{path.start_with?('/') ? path : "/#{path}"}"
  end

  def seo_canonical_url(page = current_seo_page) = seo_absolute_url(page.path)

  # The page's Open Graph image, absolute. The images task drops a 1200x630
  # PNG per page at app/assets/images/og/<key>.png (og/rules.png, ...) and it
  # is picked up with no code change; until then every page shares
  # og/default.png.
  def og_image(page = current_seo_page)
    seo_absolute_url(image_path(og_image_asset(page)))
  end

  def og_image_asset(page = current_seo_page)
    candidate = "og/#{page.key}.png"
    Rails.application.assets.load_path.find(candidate) ? candidate : DEFAULT_OG_IMAGE
  end

  # A <script type="application/ld+json"> for one schema.org object. The JSON
  # is escaped for a script element (json_escape turns <, > and & into \u
  # escapes), so a "</script>" in copy cannot close the tag early.
  def json_ld_tag(data)
    tag.script(ERB::Util.json_escape(data.to_json).html_safe, type: "application/ld+json") # rubocop:disable Rails/OutputSafety
  end

  # schema.org objects, one per method, so a view composes what it needs.

  def website_json_ld
    { "@context" => "https://schema.org", "@type" => "WebSite",
      "name" => SeoPage::SITE_NAME, "url" => seo_absolute_url("/"), "inLanguage" => "en" }
  end

  def video_game_json_ld
    home = SeoPage.find(:home)
    { "@context" => "https://schema.org", "@type" => "VideoGame",
      "name" => SeoPage::SITE_NAME, "url" => seo_absolute_url("/"),
      "description" => home.description, "image" => og_image(home),
      "genre" => "Strategy board game", "gamePlatform" => "Web browser",
      "applicationCategory" => "GameApplication", "operatingSystem" => "Any",
      "playMode" => %w[SinglePlayer MultiPlayer], "inLanguage" => "en",
      "author" => { "@type" => "Person", "name" => "Alex McRitchie" },
      "offers" => { "@type" => "Offer", "price" => "0", "priceCurrency" => "USD",
                    "availability" => "https://schema.org/InStock" } }
  end

  def faq_json_ld(faq = SeoPage.faq)
    { "@context" => "https://schema.org", "@type" => "FAQPage",
      "mainEntity" => faq.map do |question, answer|
        { "@type" => "Question", "name" => question,
          "acceptedAnswer" => { "@type" => "Answer", "text" => answer } }
      end }
  end

  def article_json_ld(page = current_seo_page)
    { "@context" => "https://schema.org", "@type" => "Article",
      "headline" => page.title, "description" => page.description,
      "url" => seo_canonical_url(page), "mainEntityOfPage" => seo_canonical_url(page),
      "image" => og_image(page), "inLanguage" => "en",
      "dateModified" => SeoPage.lastmod(page).iso8601,
      "author" => { "@type" => "Person", "name" => "Alex McRitchie" },
      "publisher" => { "@type" => "Organization", "name" => SeoPage::SITE_NAME, "url" => seo_absolute_url("/") } }
  end

  # Home > this page. The home page has no trail.
  def breadcrumb_json_ld(page = current_seo_page)
    return if page.key == :home

    home = SeoPage.find(:home)
    { "@context" => "https://schema.org", "@type" => "BreadcrumbList",
      "itemListElement" => [ home, page ].each_with_index.map do |crumb, index|
        { "@type" => "ListItem", "position" => index + 1,
          "name" => crumb.key == :home ? SeoPage::SITE_NAME : crumb.heading,
          "item" => seo_canonical_url(crumb) }
      end }
  end

  # Search Console's HTML-tag ownership check, from GOOGLE_SITE_VERIFICATION.
  def google_site_verification = ENV["GOOGLE_SITE_VERIFICATION"].to_s.strip.presence
end
