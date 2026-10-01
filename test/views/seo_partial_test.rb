require "test_helper"

# [component] layouts/_seo writes the search-engine tags only, and hands the
# link-preview card to studio-engine through link_preview (task
# cyvasse-adopts-link-preview): no og: or twitter: tag of its own, the page's
# words in the engine's preview.
class SeoPartialTest < ActionView::TestCase
  include SeoHelper

  test "a public page: search tags kept, preview tags left to the engine" do
    seo_page :rules
    render partial: "layouts/seo"

    assert_select "meta[name=description][content=?]", SeoPage.find(:rules).description
    assert_select "meta[name=robots][content=?]", "index, follow, max-image-preview:large"
    assert_select "link[rel=canonical]"
    assert_select "link[rel=apple-touch-icon]"
    assert_select "script[type='application/ld+json']"
    assert_select "meta[property^='og:']", 0
    assert_select "meta[name^='twitter:']", 0

    preview = view.studio_link_preview
    assert_equal SeoPage.find(:rules).title, preview[:title]
    assert_equal SeoPage.find(:rules).description, preview[:description]
    assert_equal "http://test.host/og.png", preview[:image], "no picture of its own: the site's"
  end

  test "a page with no SEO copy is noindex and sets no preview words" do
    render partial: "layouts/seo"

    assert_select "meta[name=robots][content=noindex]"
    assert_select "meta[property^='og:']", 0
    assert_equal Studio.site_title, view.studio_link_preview[:title]
  end
end
