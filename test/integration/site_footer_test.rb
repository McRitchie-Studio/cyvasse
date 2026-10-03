require "test_helper"

# [component] The engine's site footer as Cyvasse declares it
# (config/initializers/studio.rb, site_footer; task cyvasse-footer-and-legal):
# its links and their targets, what it must never carry (an address, a map, a
# phone, a booking popup), and where it shows.
class SiteFooterTest < ActionDispatch::IntegrationTest
  FOOTER = "footer[data-site-footer]".freeze

  # [column heading, [[label, href], ...]] in the order the footer prints them.
  COLUMNS = [
    [ "Play", [ [ "Play the computer", "/play" ], [ "Cyvasse Night", "/night" ], [ "Leaderboard", "/leaderboard" ] ] ],
    [ "Learn", [ [ "Rules", "/rules" ], [ "Pieces", "/pieces" ], [ "About", "/about" ] ] ],
    [ "Legal", [ [ "Privacy Policy", "/privacy" ], [ "Terms of Service", "/terms" ] ] ]
  ].freeze

  test "the home page ends with the footer: brand, tagline, contact email" do
    get root_path

    assert_response :success
    assert_select FOOTER, 1
    assert_select "#{FOOTER} a.ftr-home[href=?]", "/" do
      assert_select "img[src=?]", "/icon.png"
      assert_select ".ftr-wordmark", text: "Cyvasse"
    end
    assert_select "#{FOOTER} .ftr-tagline", text: "The hex-board strategy game from A Song of Ice and Fire, free in your browser."
    assert_select "#{FOOTER} .ftr-email a[href=?]", "mailto:team@mcritchie.studio", text: "team@mcritchie.studio"
    assert_select "#{FOOTER} .ftr-copyright", text: "© #{Time.current.year} Cyvasse by McRitchie Studio LLC"
  end

  test "every column link is the app's own page, in order, opening in the same tab" do
    get root_path

    columns = css_select("#{FOOTER} nav.ftr-col")
    assert_equal COLUMNS.map(&:first), columns.map { |col| col.at_css(".ftr-heading").text.strip }

    COLUMNS.zip(columns).each do |(heading, links), col|
      found = col.css("a.ftr-link").map { |a| [ a.text.strip, a["href"] ] }
      assert_equal links, found, "the #{heading} column"
      col.css("a.ftr-link").each do |a|
        assert_nil a["target"], "#{a.text.strip} is a page on this site and stays in the tab"
      end
    end
    assert_select "#{FOOTER} .ftr-link-disabled", false, "no column carries a page that does not exist"
  end

  test "every footer link answers, signed out" do
    get root_path
    hrefs = css_select("#{FOOTER} a[href^='/']").map { |a| a["href"] }.uniq
    assert_operator hrefs.size, :>=, 9

    hrefs.each do |href|
      get href
      assert_response :success, "#{href} must render for a visitor"
    end
  end

  test "the legal line links the Privacy Policy and the Terms" do
    get root_path

    assert_select "#{FOOTER} .ftr-legal a", count: 2
    assert_select "#{FOOTER} .ftr-legal a[href=?]", "/privacy", text: "Privacy Policy"
    assert_select "#{FOOTER} .ftr-legal a[href=?]", "/terms", text: "Terms of Service"
  end

  test "no address, map, phone, social row or booking popup" do
    get root_path

    assert_select "#{FOOTER} [data-footer-location]", false
    assert_select "#{FOOTER} [data-footer-map]", false
    assert_select "#{FOOTER} .ftr-location", false
    assert_select "#{FOOTER} a[href^='tel:']", false
    assert_select "#{FOOTER} .ftr-social", false
    assert_select "[data-booking-popup], [data-booking-link], iframe", false
    # A footer with no address requests neither Leaflet nor a tile. The engine's
    # inline map script still ships, dormant: it acts only on a [data-footer-map]
    # element, asserted absent above, so look at what loads, not at the words.
    # test/system/site_footer_rows_test.rb checks the browser fetched neither.
    assert_select "script[src*=leaflet], link[href*=leaflet], [data-leaflet-js]", false
  end

  test "a visitor sees it on the public reading pages and the sign-in page" do
    [ root_path, rules_path, pieces_path, about_path, leaderboard_path, night_path, privacy_path, terms_path, signin_path ].each do |path|
      get path
      assert_response :success
      assert_select FOOTER, 1, "#{path} shows the footer to a visitor"
    end
  end

  test "the board against the computer stays clean, even for a visitor" do
    get play_path

    assert_response :success
    assert_select FOOTER, false
  end

  test "a signed-in player sees it on the reading pages, never on the working surfaces" do
    log_in_as(User.create!(email: "carl@example.com", name: "Carl Test", username: "carl"))

    [ root_path, rules_path, leaderboard_path, night_path, privacy_path, terms_path ].each do |path|
      get path
      assert_response :success
      assert_select FOOTER, 1, "#{path} keeps the footer for a player"
    end

    [ play_path, matches_path, conversations_path, "/profile" ].each do |path|
      get path
      assert_response :success
      assert_select FOOTER, false, "#{path} is a working surface"
    end
  end
end
