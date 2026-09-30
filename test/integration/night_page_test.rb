require "test_helper"

# [integration] Cyvasse Night through the whole stack (task
# cyvasse-night-event-page): /night before, during and after the night, its
# calendar file, its SEO head and Event JSON-LD, and the home page's banner.
class NightPageTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  include SeoAssertions
  include LiveResults

  CANONICAL = "cyvasse.xyz".freeze

  setup do
    @night = CyvasseNight.current
    @previous = ENV["CANONICAL_HOST"]
    ENV["CANONICAL_HOST"] = CANONICAL
    host! CANONICAL
    https!
  end

  teardown { ENV["CANONICAL_HOST"] = @previous }

  test "before: the Mountain time on the server, a countdown, calendar links and how it works; no Play Now yet" do
    travel_to(@night.starts_at - (2.days + 3.hours + 4.minutes + 5.seconds)) { get night_path }

    assert_response :success
    assert_select "article[data-night-phase=before]"
    assert_select "h1", /Cyvasse Night\s*·\s*Tuesday, October 6\s*·\s*7 PM Mountain/
    assert_select "time[datetime=?]", "2026-10-06T19:00:00-06:00", /Tuesday, October 6, 7–10 PM Mountain/
    assert_select "[data-controller=night-countdown][data-night-countdown-start-value=?]", "2026-10-06T19:00:00-06:00"
    assert_select "[data-night-countdown-phase-value=before]"
    assert_select "[data-night-local][hidden]", 1, "the local time waits for the browser to know its zone"
    assert_select ".night-countdown-label", "Starts in"
    assert_equal %w[2 03 04 05], css_select(".night-countdown-value").map { |node| node.text.strip }

    assert_select "a[data-night-ics][href=?]", "/night.ics"
    google = css_select("a[data-night-google]").first
    assert_equal "_blank", google["target"]
    assert_includes google["href"], "https://calendar.google.com/calendar/render?"
    assert_includes google["href"], "dates=20261007T010000Z%2F20261007T040000Z"
    how = css_select("[data-night-how]").first.text.squish
    assert_match(/Come at 7 PM Mountain/, how)
    assert_match(/Press Play Now/, how)
    assert_match(/matched live/, how)
    assert_match(/Top the leaderboard/, how)

    assert_select "article form[action=?]", live_seeks_path, 0, "Play Now waits for the night"
    assert_select "[data-night-leaderboard]", 0
    assert_select "[data-night-presence]", 0
  end

  test "during: Play Now, who is here, the time left, and tonight's leaderboard" do
    arya = player("arya")
    sansa = player("sansa")
    live_result(arya, sansa, winner: arya, finished_at: @night.starts_at - 1.day)
    live_result(sansa, arya, winner: sansa, finished_at: @night.starts_at + 10.minutes)
    now = @night.starts_at + 30.minutes
    LiveSeek.create!(user: player("bran"), last_seen_at: now)

    travel_to(now) { get night_path }

    assert_response :success
    assert_select "article[data-night-phase=during]"
    assert_select "[data-night-kicker]", /Live now/
    assert_select "form[action=?] button.btn-primary", live_seeks_path, "Play Now"
    assert_select "[data-night-presence]", /1 player\s+online · 1 searching now/
    assert_select ".night-countdown-label", "Ends in"
    assert_equal %w[0 02 30 00], css_select(".night-countdown-value").map { |node| node.text.strip }
    assert_select "[data-night-calendar]", 0, "no calendar once it has started"

    board = css_select("[data-night-leaderboard] [data-leaderboard-row]")
    assert_equal %w[sansa arya], board.map { |row| row["data-leaderboard-row"] }, "only tonight's game counts"
    assert_select "[data-night-leaderboard] [data-leaderboard-row=sansa] [data-stat=wins]", /1/
    assert_select "[data-night-leaderboard] [data-leaderboard-row=arya] [data-stat=wins]", /0/
  end

  test "during with nobody here yet invites the first player" do
    travel_to(@night.starts_at + 1.minute) { get night_path }

    assert_select "[data-night-presence]", /Be the first here/
    assert_select "[data-night-leaderboard-empty]", /No games finished yet tonight/
  end

  test "after: the next night is coming, the leaderboard is a link away, and no countdown" do
    arya = player("arya")
    live_result(arya, player("sansa"), winner: arya, finished_at: @night.starts_at + 1.hour)

    travel_to(@night.ends_at + 1.hour) { get night_path }

    assert_response :success
    assert_select "article[data-night-phase=after]"
    assert_select "[data-night-next] h2", "Next Cyvasse Night coming soon"
    assert_select "[data-night-next] a[href=?]", leaderboard_path
    assert_select "[data-night-countdown]", 0
    assert_select "article form[action=?]", live_seeks_path, 0
    assert_select "[data-night-calendar]", 0
    assert_select "[data-night-leaderboard] [data-leaderboard-row=arya]", 1, "tonight's final board"
  end

  test "the calendar file downloads as text/calendar" do
    get "/night.ics"

    assert_response :success
    assert_equal "text/calendar", response.media_type
    assert_match(/attachment; filename="cyvasse-night-2026-10-06.ics"/, response.headers["Content-Disposition"])
    assert response.body.start_with?("BEGIN:VCALENDAR\r\n")
    assert_includes response.body, "DTSTART:20261007T010000Z"
    assert_includes response.body.gsub("\r\n ", ""), "URL:https://#{CANONICAL}/night"
  end

  test "the page is public, indexed, and names itself an online Event in its JSON-LD" do
    get night_path

    doc = page_doc
    page = SeoPage.find(:night)
    assert_equal page.title, doc.at_css("head > title").text
    assert_equal "https://#{CANONICAL}/night", meta_content(doc, 'link[rel="canonical"]')
    assert_equal "index, follow, max-image-preview:large", meta_content(doc, 'meta[name="robots"]')
    assert_equal page.description, meta_content(doc, 'meta[property="og:description"]')
    assert_equal "https://#{CANONICAL}/night", meta_content(doc, 'meta[property="og:url"]')

    event = json_ld_blocks(doc).find { |block| block["@type"] == "Event" }
    assert event, "an Event block"
    assert_equal "2026-10-06T19:00:00-06:00", event["startDate"]
    assert_equal "https://schema.org/OnlineEventAttendanceMode", event["eventAttendanceMode"]
    assert_equal({ "@type" => "VirtualLocation", "url" => "https://#{CANONICAL}/night" }, event["location"])
    assert_match %r{\Ahttps://#{Regexp.escape(CANONICAL)}/assets/og/default-\h+\.png\z}, event["image"].first
    assert json_ld_blocks(doc).any? { |block| block["@type"] == "BreadcrumbList" }
  end

  test "the page preloads its countdown and none of the game" do
    get night_path

    preloads = css_select("link[rel=modulepreload]").map { |link| link["href"] }
    assert(preloads.any? { |href| href.include?("night_countdown_controller") })
    assert(preloads.any? { |href| href.include?("night_clock") })
    assert(preloads.none? { |href| href.include?("cyvasse_game_controller") })
    # A restored snapshot would freeze serverTime and tick a stale countdown.
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
  end

  test "the home page links to the night until it is over, and says so while it runs" do
    travel_to(@night.starts_at - 1.day) { get root_path }
    assert_select "section.home-hero a[data-night-banner][href=?]", night_path, /Cyvasse Night · Tue Oct 6, 7 PM MT/

    travel_to(@night.starts_at + 1.hour) { get root_path }
    assert_select "a[data-night-banner]", /Cyvasse Night · Live now/

    travel_to(@night.ends_at) { get root_path }
    assert_select "a[data-night-banner]", 0
  end

  test "the sitemap lists the night" do
    get "/sitemap.xml"

    locs = Nokogiri::XML(response.body).xpath("//s:loc", "s" => "http://www.sitemaps.org/schemas/sitemap/0.9").map(&:text)
    assert_includes locs, "https://#{CANONICAL}/night"
  end
end
