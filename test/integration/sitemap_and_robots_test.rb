require "test_helper"

# [integration] /sitemap.xml and /robots.txt (task cyvasse-seo-profile).
class SitemapAndRobotsTest < ActionDispatch::IntegrationTest
  CANONICAL = "cyvasse.xyz".freeze
  SITEMAP_NS = "http://www.sitemaps.org/schemas/sitemap/0.9".freeze

  setup do
    @previous = ENV["CANONICAL_HOST"]
    ENV["CANONICAL_HOST"] = CANONICAL
    host! CANONICAL
    https!
  end

  teardown { ENV["CANONICAL_HOST"] = @previous }

  test "the sitemap is valid XML listing every public page on the canonical host" do
    get "/sitemap.xml"

    assert_response :success
    assert_equal "application/xml", response.media_type
    doc = Nokogiri::XML(response.body) { |config| config.strict }
    assert_equal SITEMAP_NS, doc.root.namespace.href
    assert_equal "urlset", doc.root.name

    urls = doc.xpath("//s:url", "s" => SITEMAP_NS)
    locs = urls.map { |url| url.at_xpath("s:loc", "s" => SITEMAP_NS).text }
    assert_equal %w[/ /play /rules /pieces /about /leaderboard /night].map { |path| "https://#{CANONICAL}#{path}" }, locs

    urls.each do |url|
      lastmod = url.at_xpath("s:lastmod", "s" => SITEMAP_NS).text
      assert_match(/\A\d{4}-\d{2}-\d{2}\z/, lastmod)
      assert_equal lastmod, Date.iso8601(lastmod).iso8601
      assert_includes %w[always hourly daily weekly monthly yearly never], url.at_xpath("s:changefreq", "s" => SITEMAP_NS).text
      assert_includes 0.0..1.0, url.at_xpath("s:priority", "s" => SITEMAP_NS).text.to_f
    end
  end

  test "the sitemap needs no sign-in and every page it lists answers 200" do
    get "/sitemap.xml"
    paths = Nokogiri::XML(response.body).xpath("//s:loc", "s" => SITEMAP_NS).map { |loc| URI(loc.text).path }

    paths.each do |path|
      get path
      assert_response :success, path
    end
  end

  test "robots.txt allows the site, disallows the private paths and names the sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_equal "text/plain", response.media_type
    lines = response.body.lines(chomp: true)
    assert_equal [ "User-agent: *", "Allow: /" ], lines.first(2)
    %w[/admin /api/ /matches /live/ /inbox /conversations /onboarding /signin /login /magic_link /auth/ /account/
       /leaderboard/join].each do |path|
      assert_includes lines, "Disallow: #{path}"
    end
    assert_equal "Sitemap: https://#{CANONICAL}/sitemap.xml", lines.last
  end

  test "robots.txt blocks no public page" do
    get "/robots.txt"
    disallowed = response.body.lines(chomp: true).filter_map { |line| line.delete_prefix("Disallow: ") if line.start_with?("Disallow:") }

    SeoPage::PAGES.map { |page| URI(page.path).path }.uniq.each do |path|
      blocking = disallowed.select { |prefix| path.start_with?(prefix) }
      assert_empty blocking, "#{path} must stay crawlable"
    end
  end

  test "the Rails default robots.txt in public/ is gone, so the route answers" do
    assert_not File.exist?(Rails.public_path.join("robots.txt"))
  end
end
