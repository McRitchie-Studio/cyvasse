require "test_helper"

# [unit] SeoHelper: absolute URLs on the canonical host, the Open Graph image
# slot, and JSON-LD that a copy cannot break out of (task cyvasse-seo-profile).
class SeoHelperTest < ActionView::TestCase
  include SeoHelper

  setup do
    @previous = ENV["CANONICAL_HOST"]
    @previous_verification = ENV["GOOGLE_SITE_VERIFICATION"]
  end

  teardown do
    ENV["CANONICAL_HOST"] = @previous
    ENV["GOOGLE_SITE_VERIFICATION"] = @previous_verification
  end

  test "absolute URLs use the canonical host whatever host the request came in on" do
    ENV["CANONICAL_HOST"] = "cyvasse.xyz"
    controller.request.host = "cyvasse.mcritchie.studio"

    assert_equal "https://cyvasse.xyz/rules", seo_canonical_url(SeoPage.find(:rules))
    assert_equal "https://cyvasse.xyz/leaderboard?board=all-time", seo_canonical_url(SeoPage.find(:all_time_leaderboard))
    # The digested /assets/ path is pinned by test/integration/seo_meta_test.rb,
    # where the asset pipeline resolves it.
    assert_match %r{\Ahttps://cyvasse\.xyz/.*og/default}, og_image(SeoPage.find(:rules))
  end

  test "with no canonical host (a desk, a test) the request's own origin stands in" do
    ENV["CANONICAL_HOST"] = nil

    assert_equal "http://test.host/about", seo_canonical_url(SeoPage.find(:about))
  end

  test "a page without its own art shares the default card; one dropped in og/ is used" do
    page = SeoPage.find(:pieces)
    assert_equal "og/default.png", og_image_asset(page)

    assert og_asset_exists?("og/default.png"), "the default card is a real asset"
    assert_not og_asset_exists?("og/pieces.png")

    # The images task drops og/pieces.png: the load path now finds it.
    define_singleton_method(:og_asset_exists?) { |path| path == "og/pieces.png" }
    assert_equal "og/pieces.png", og_image_asset(page)
    assert_equal "og/default.png", og_image_asset(SeoPage.find(:rules))
  end

  test "a page's own preview image is og/<key>.png, else nil so the site image answers" do
    ENV["CANONICAL_HOST"] = "cyvasse.xyz"
    assert_nil og_page_image(SeoPage.find(:pieces)), "no og/pieces.png: the card falls back"

    define_singleton_method(:og_asset_exists?) { |path| path == "og/pieces.png" }
    define_singleton_method(:image_path) { |path| "/assets/#{path}" }
    assert_equal "https://cyvasse.xyz/assets/og/pieces.png", og_page_image(SeoPage.find(:pieces))
    assert_nil og_page_image(SeoPage.find(:rules))
  end

  test "JSON-LD escapes a closing script tag in copy" do
    html = json_ld_tag({ "name" => "</script><script>alert(1)</script>" })

    assert_equal 1, html.scan("</script>").size, "only the tag's own close"
    parsed = JSON.parse(Nokogiri::HTML5.fragment(html).at_css("script").text)
    assert_equal "</script><script>alert(1)</script>", parsed["name"]
  end

  test "the breadcrumb is Home then the page, and the home page has none" do
    ENV["CANONICAL_HOST"] = "cyvasse.xyz"
    trail = breadcrumb_json_ld(SeoPage.find(:rules))

    assert_equal "BreadcrumbList", trail["@type"]
    assert_equal [ [ 1, "Cyvasse", "https://cyvasse.xyz/" ], [ 2, "Rules", "https://cyvasse.xyz/rules" ] ],
                 trail["itemListElement"].map { |item| item.values_at("position", "name", "item") }
    assert_nil breadcrumb_json_ld(SeoPage.find(:home))
  end

  test "the verification token is read from GOOGLE_SITE_VERIFICATION, blank as unset" do
    ENV["GOOGLE_SITE_VERIFICATION"] = nil
    assert_nil google_site_verification
    ENV["GOOGLE_SITE_VERIFICATION"] = "  "
    assert_nil google_site_verification
    ENV["GOOGLE_SITE_VERIFICATION"] = "abc123"
    assert_equal "abc123", google_site_verification
  end
end
