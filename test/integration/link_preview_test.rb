require "test_helper"

# [integration] Cyvasse's link-preview card is studio-engine's (task
# cyvasse-adopts-link-preview; studio-engine docs/LINK_PREVIEW.md), through the
# whole stack:
#
# - a public page unfurls with its own words, over the operator's;
# - its own picture wins when it has one, and without one the card falls back
#   to the operator's site image, then to public/og.png;
# - a page that names no SEO copy unfurls with the site identity;
# - every tag appears once (the engine's set, never a second one of ours);
# - a preview bot gets the slim page, under Apple's 1 MiB limit, and a person
#   the full one.
class LinkPreviewTest < ActionDispatch::IntegrationTest
  include SeoAssertions

  CANONICAL = "cyvasse.xyz".freeze
  # What iMessage sends (studio-engine LINK_PREVIEW.md).
  IMESSAGE = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_1) AppleWebKit/601.2.4 (KHTML, like Gecko) " \
             "Version/9.0.1 Safari/601.2.4 facebookexternalhit/1.1 Facebot Twitterbot/1.0".freeze
  SAFARI = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) " \
           "Version/18.0 Safari/605.1.15".freeze
  APPLE_LIMIT = 1_048_576
  PUBLIC = %w[/ /play /rules /pieces /about /leaderboard].freeze
  PNG = Rails.root.join("public/og.png")

  setup do
    @previous = ENV["CANONICAL_HOST"]
    ENV["CANONICAL_HOST"] = CANONICAL
    host! CANONICAL
    https!
  end

  teardown do
    ENV["CANONICAL_HOST"] = @previous
    Studio::SiteIdentity.bust_cache!
  end

  test "the engine writes the tags, once each, and none of ours is left" do
    assert Studio.link_preview_tags?, "link_preview_tags :auto is on: no template here writes its own og tags"

    PUBLIC.each do |path|
      get path
      assert_response :success, path
      %w[og:title og:description og:image og:url og:site_name].each do |property|
        assert_equal 1, page_doc.css("meta[property='#{property}']").size, "#{path}: one #{property}"
      end
      %w[twitter:card twitter:title twitter:image].each do |name|
        assert_equal 1, page_doc.css("meta[name='#{name}']").size, "#{path}: one #{name}"
      end
    end
  end

  test "a public page's own words win over the operator's" do
    Studio::SiteIdentity.current!.update!(title: "Operator title", description: "Operator description")

    get "/rules"
    rules = SeoPage.find(:rules)
    assert_equal rules.title, og(:title)
    assert_equal rules.description, og(:description)
    assert_equal rules.title, meta_content(page_doc, 'meta[name="twitter:title"]')

    # A page with no SEO copy of its own unfurls with the operator's.
    get "/signin"
    assert_equal "Operator title", og(:title)
    assert_equal "Operator description", og(:description)
  end

  test "with nothing saved, the drafted identity and public/og.png answer" do
    get "/signin"
    assert_equal Studio.site_title, og(:title)
    assert_equal Studio.site_description, og(:description)
    assert_equal "https://#{CANONICAL}/og.png", og(:image)
    assert PNG.file?, "public/og.png, the last-resort card, is in the app"
  end

  test "a page without its own picture falls back to the operator's site image" do
    identity = Studio::SiteIdentity.current!
    identity.image.attach(io: PNG.open, filename: "card.png", content_type: "image/png")
    Studio::SiteIdentity.bust_cache!

    get "/rules"
    assert_match %r{\Ahttps://#{Regexp.escape(CANONICAL)}/rails/active_storage/.+/card\.png\z}, og(:image),
                 "the operator's image, through the permanent proxy URL"
    assert_equal og(:image), meta_content(page_doc, 'meta[name="twitter:image"]')
    assert_equal "summary_large_image", meta_content(page_doc, 'meta[name="twitter:card"]')
  end

  test "a page with its own picture keeps it over the operator's" do
    identity = Studio::SiteIdentity.current!
    identity.image.attach(io: PNG.open, filename: "card.png", content_type: "image/png")
    Studio::SiteIdentity.bust_cache!

    # The images task drops og/rules.png; stand that in for the asset lookup.
    with_page_image("og/rules.png", stands_in_for: "og/default.png") do
      get "/rules"
      assert_match %r{\Ahttps://#{Regexp.escape(CANONICAL)}/assets/og/default-\h+\.png\z}, og(:image)
      get "/about"
      assert_match %r{/rails/active_storage/.+/card\.png\z}, og(:image), "a page without one still falls back"
    end
  end

  test "a preview bot gets the slim page under 1 MiB, with the card" do
    PUBLIC.each do |path|
      get path, headers: { "User-Agent" => IMESSAGE }
      assert_response :success, path
      assert_equal "slim", response.headers["X-Studio-Link-Preview"], path
      assert_includes response.headers["Vary"].to_s, "User-Agent", path
      assert_operator response.body.bytesize, :<, APPLE_LIMIT, "#{path}: under Apple's 1 MiB"
      assert_empty page_doc.css("script:not([type='application/ld+json']), style, template"), "#{path}: no script, style or template"
      assert_equal SeoPage::PAGES.find { |page| page.path == path }.title, og(:title), path
      assert og(:image).present?, "#{path}: an image"
    end
  end

  test "a person gets the full page" do
    get "/rules", headers: { "User-Agent" => SAFARI }
    assert_response :success
    assert_nil response.headers["X-Studio-Link-Preview"]
    assert page_doc.at_css("main"), "the whole page"
    assert_equal SeoPage.find(:rules).title, og(:title)
  end

  private

  def og(key) = meta_content(page_doc, "meta[property='og:#{key}']")

  # Makes SeoHelper see `path` as an asset and resolve it to `stands_in_for`
  # (a real asset, so image_path can digest it), for the block.
  def with_page_image(path, stands_in_for:)
    exists = SeoHelper.instance_method(:og_asset_exists?)
    resolve = SeoHelper.instance_method(:og_image)
    SeoHelper.define_method(:og_asset_exists?) { |candidate| candidate == path || exists.bind_call(self, candidate) }
    SeoHelper.define_method(:og_image) do |page = current_seo_page|
      og_image_asset(page) == path ? seo_absolute_url(image_path(stands_in_for)) : resolve.bind_call(self, page)
    end
    yield
  ensure
    SeoHelper.define_method(:og_asset_exists?, exists)
    SeoHelper.define_method(:og_image, resolve)
  end
end
