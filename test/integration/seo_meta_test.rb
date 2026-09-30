require "test_helper"

# [integration] The SEO head of every page through the whole stack (task
# cyvasse-seo-profile): each public page has its own title, description,
# canonical, Open Graph and Twitter card, exactly one h1 and JSON-LD that
# parses; every private page is noindex.
class SeoMetaTest < ActionDispatch::IntegrationTest
  include SeoAssertions
  include MatchPlay

  CANONICAL = "cyvasse.xyz".freeze
  PUBLIC = {
    "/" => :home, "/play" => :play, "/rules" => :rules, "/pieces" => :pieces,
    "/about" => :about, "/leaderboard" => :leaderboard, "/leaderboard?board=all-time" => :all_time_leaderboard
  }.freeze
  GOOGLEBOT = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) " \
              "Chrome/129.0.6668.70 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)".freeze

  setup do
    @previous = ENV.slice("CANONICAL_HOST", "GOOGLE_SITE_VERIFICATION")
    ENV["CANONICAL_HOST"] = CANONICAL
    ENV.delete("GOOGLE_SITE_VERIFICATION")
    host! CANONICAL
    https!
  end

  teardown do
    %w[CANONICAL_HOST GOOGLE_SITE_VERIFICATION].each { |key| ENV[key] = @previous[key] }
  end

  test "every public page has its own title, description, canonical and social card" do
    seen = PUBLIC.map do |path, key|
      get path
      assert_response :success, path
      page = SeoPage.find(key)
      doc = page_doc
      canonical = "https://#{CANONICAL}#{page.path}"

      assert_equal page.title, doc.at_css("head > title").text, path
      assert_equal 1, doc.css("head > title").size
      assert_equal page.description, meta_content(doc, 'meta[name="description"]'), path
      assert_equal canonical, meta_content(doc, 'link[rel="canonical"]'), path
      assert_equal "index, follow, max-image-preview:large", meta_content(doc, 'meta[name="robots"]'), path

      assert_equal page.title, meta_content(doc, 'meta[property="og:title"]'), path
      assert_equal page.description, meta_content(doc, 'meta[property="og:description"]'), path
      assert_equal canonical, meta_content(doc, 'meta[property="og:url"]'), path
      assert_equal "Cyvasse", meta_content(doc, 'meta[property="og:site_name"]')
      assert_match %r{\Ahttps://#{Regexp.escape(CANONICAL)}/assets/og/default-\h+\.png\z},
                   meta_content(doc, 'meta[property="og:image"]'), "#{path}: an absolute, digested image URL"
      assert_equal %w[1200 630], [ meta_content(doc, 'meta[property="og:image:width"]'), meta_content(doc, 'meta[property="og:image:height"]') ]
      assert_equal "summary_large_image", meta_content(doc, 'meta[name="twitter:card"]')
      assert_equal page.title, meta_content(doc, 'meta[name="twitter:title"]')
      assert_equal meta_content(doc, 'meta[property="og:image"]'), meta_content(doc, 'meta[name="twitter:image"]')

      # The page's own heading. The engine navbar renders the app name in an
      # <h1 class="nav-title"> on every page (studio-engine layouts/_navbar);
      # that one is the engine's to change, so it is left out here.
      assert_equal 1, doc.css("h1:not(.nav-title)").size, "#{path}: exactly one h1 of its own"
      assert_equal "en", doc.at_css("html")["lang"]
      assert doc.at_css('meta[name="viewport"]'), "#{path}: a viewport"
      assert doc.at_css('link[rel="apple-touch-icon"]') && doc.at_css('link[rel="icon"]'), "#{path}: icons"
      # Content images carry a src; the engine flash toast's Alpine <img :src> is chrome.
      assert_empty doc.css("main img[src]:not([alt])").map { |img| img["src"] }, "#{path}: every content image has alt text"

      json_ld_blocks(doc).each { |block| assert_equal "https://schema.org", block["@context"] }
      page.title
    end
    assert_equal seen.uniq, seen
  end

  test "the home page's structured data: WebSite, VideoGame and the FAQ it shows" do
    get root_path
    blocks = json_ld_blocks.index_by { |block| block["@type"] }

    assert_equal %w[FAQPage VideoGame WebSite], blocks.keys.sort
    assert_equal({ "@context" => "https://schema.org", "@type" => "WebSite", "name" => "Cyvasse",
                   "url" => "https://#{CANONICAL}/", "inLanguage" => "en" }, blocks["WebSite"])

    game = blocks["VideoGame"]
    assert_equal [ "Cyvasse", "https://#{CANONICAL}/", "Strategy board game", "Web browser" ],
                 game.values_at("name", "url", "genre", "gamePlatform")
    assert_equal [ "Offer", "0" ], game["offers"].values_at("@type", "price")
    assert_match %r{\Ahttps://}, game["image"]

    faq = blocks["FAQPage"]["mainEntity"]
    assert_equal SeoPage.faq.map(&:first), faq.map { |item| item["name"] }
    shown = page_doc.css("#faq dt, #faq dd").map { |node| node.text.squish }
    faq.each do |item|
      assert_includes shown, item["name"], "the FAQ question is on the page"
      assert_includes shown, item["acceptedAnswer"]["text"], "the FAQ answer is on the page, word for word"
    end
  end

  test "the home page tells a crawler what Cyvasse is, in the HTML" do
    get root_path

    intro = page_doc.at_css("#what-is-cyvasse").text.squish
    assert_match(/strategy board game/, intro)
    assert_match(/free to play online/, intro)
    assert_select "#what-is-cyvasse a[href=?]", rules_path
  end

  test "the rules page is an Article with a breadcrumb; inner pages carry a breadcrumb" do
    get rules_path
    blocks = json_ld_blocks.index_by { |block| block["@type"] }

    assert_equal %w[Article BreadcrumbList], blocks.keys.sort
    assert_equal "https://#{CANONICAL}/rules", blocks["Article"]["mainEntityOfPage"]
    assert_equal SeoPage.find(:rules).title, blocks["Article"]["headline"]

    %w[/play /pieces /about /leaderboard].each do |path|
      get path
      trail = json_ld_blocks.find { |block| block["@type"] == "BreadcrumbList" }
      assert trail, "#{path} has a breadcrumb"
      assert_equal "https://#{CANONICAL}#{path}", trail["itemListElement"].last["item"]
    end
  end

  test "the public pages render their words on the server, not only in script" do
    { "/" => "What is Cyvasse?", "/rules" => "Capture your opponent's king", "/pieces" => "The Pieces",
      "/about" => "George R. R. Martin", "/leaderboard" => "Live games since the relaunch",
      # The board itself is drawn by script; its heading and panels are not.
      "/play" => "Play Cyvasse" }.each do |path, text|
      get path
      body = page_doc.at_css("main")
      body.css("script, template, style").each(&:remove)
      assert_includes body.text.squish, text, "#{path} renders its words in the HTML"
    end
  end

  test "a crawler is served, not turned away as an old browser" do
    PUBLIC.each_key do |path|
      get path, headers: { "User-Agent" => GOOGLEBOT }
      assert_response :success, path
    end
  end

  test "sign-in, onboarding and the other private pages are noindex and carry no canonical" do
    %w[/signin /login /leaderboard/join].each do |path|
      get path
      assert_response :success, path
      assert_noindex path
    end

    arya = make_player("arya")
    log_in_as(arya)
    post live_seeks_path
    seek = LiveSeek.last
    get live_seek_path(seek)
    assert_noindex "/live/:id"

    post matches_path, params: { username: make_player("brienne").username }
    get match_path(Match.last)
    assert_response :success
    assert_noindex "/matches/:id"

    %w[/matches /inbox /username].each do |path|
      get path
      assert_response :success, path
      assert_noindex path
    end
  end

  test "the admin pages are noindex" do
    log_in_as(User.create!(email: "admin@example.com", name: "Admin", role: "admin", username: "boss"))

    [ admin_message_board_path, admin_conversations_path, admin_sign_ins_path ].each do |path|
      get path
      assert_response :success, path
      assert_noindex path
    end
  end

  test "the Search Console tag renders only when GOOGLE_SITE_VERIFICATION is set" do
    get root_path
    assert_select 'meta[name="google-site-verification"]', 0

    ENV["GOOGLE_SITE_VERIFICATION"] = "abc123-token"
    get root_path
    assert_select 'meta[name="google-site-verification"][content="abc123-token"]', 1
  end

  private

  def assert_noindex(path)
    doc = page_doc
    assert_equal "noindex", meta_content(doc, 'meta[name="robots"]'), "#{path} is noindex"
    assert_nil doc.at_css('link[rel="canonical"]'), "#{path} names no canonical"
    assert_nil doc.at_css('meta[property="og:title"]'), "#{path} has no social card"
    assert_empty json_ld_blocks(doc), "#{path} has no structured data"
  end
end
