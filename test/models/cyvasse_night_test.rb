require "test_helper"

# [unit] CyvasseNight (task cyvasse-night-event-page): the event's window, its
# labels, the calendar file, the Google Calendar link, the players-online
# count and tonight's leaderboard.
class CyvasseNightTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include LiveResults

  MOUNTAIN = Time.find_zone("America/Denver")

  setup { @night = CyvasseNight.current }

  test "the next night is Tuesday, October 6, 2026 at 7 PM Mountain, for three hours" do
    assert_equal MOUNTAIN.parse("2026-10-06 19:00"), CyvasseNight::NEXT
    assert_equal Time.utc(2026, 10, 7, 1), @night.starts_at.utc, "7 PM MDT is 01:00 UTC the next day"
    assert_equal Time.utc(2026, 10, 7, 4), @night.ends_at.utc
    assert_equal "America/Denver", @night.starts_at.time_zone.name
  end

  test "before the start it is before, at 7:00 PM exactly it is on, at 10:00 PM exactly it is over" do
    travel_to MOUNTAIN.parse("2026-09-30 12:00") do
      assert_equal :before, @night.phase
      assert @night.before?
      assert @night.banner?
    end
    travel_to @night.starts_at - 1.second do
      assert_equal :before, @night.phase
    end
    travel_to @night.starts_at do
      assert_equal :during, @night.phase
      assert @night.during?
      assert @night.banner?, "the banner stays up while the night runs"
    end
    travel_to @night.ends_at - 1.second do
      assert_equal :during, @night.phase
    end
    travel_to @night.ends_at do
      assert_equal :after, @night.phase
      assert @night.after?
      assert_not @night.banner?, "the banner is gone once the night is over"
    end
  end

  test "phase takes an explicit time, and another night is one argument" do
    other = CyvasseNight.new(starts_at: MOUNTAIN.parse("2026-11-03 18:30"), duration: 2.hours)

    assert_equal :before, other.phase(MOUNTAIN.parse("2026-11-03 18:29"))
    assert_equal :during, other.phase(MOUNTAIN.parse("2026-11-03 20:29"))
    assert_equal :after, other.phase(MOUNTAIN.parse("2026-11-03 20:30"))
    assert_equal "6:30 PM Mountain", other.time_label
    assert_equal "6:30–8:30 PM Mountain", other.window_label
  end

  test "the labels the page, the banner and the SEO copy read" do
    assert_equal "Tuesday, October 6", @night.date_label
    assert_equal "Tue Oct 6", @night.short_date_label
    assert_equal "7 PM Mountain", @night.time_label
    assert_equal "7 PM MT", @night.short_time_label
    assert_equal "7–10 PM Mountain", @night.window_label
    assert_includes SeoPage.find(:night).description, "Tuesday, October 6 at 7 PM Mountain"
  end

  test "the calendar file is one VEVENT in UTC with CRLF lines of at most 75 octets" do
    url = "https://cyvasse.xyz/night"
    ics = travel_to(Time.utc(2026, 9, 30, 12)) { @night.to_ics(url) }

    assert ics.end_with?("\r\n")
    lines = ics.split("\r\n")
    assert_equal "BEGIN:VCALENDAR", lines.first
    assert_equal "END:VCALENDAR", lines.last
    assert_empty ics.gsub("\r\n", "").scan("\n"), "no bare LF"
    lines.each { |line| assert_operator line.bytesize, :<=, 75, line }

    unfolded = ics.gsub("\r\n ", "").split("\r\n")
    assert_equal 1, unfolded.count("BEGIN:VEVENT")
    assert_includes unfolded, "VERSION:2.0"
    assert_includes unfolded, "DTSTART:20261007T010000Z"
    assert_includes unfolded, "DTEND:20261007T040000Z"
    assert_includes unfolded, "DTSTAMP:20260930T120000Z"
    assert_includes unfolded, "SUMMARY:Cyvasse Night"
    assert_includes unfolded, "URL:#{url}"
    assert_includes unfolded, "UID:cyvasse-night-20261007@cyvasse.xyz"
    assert_includes unfolded, "TRIGGER:-PT15M"
    description = unfolded.find { |line| line.start_with?("DESCRIPTION:Everyone") }
    assert_includes description, "press Play Now", "the how-to rides in the event"
    assert_includes description, "\\,", "commas are escaped as RFC 5545 TEXT"
    assert_includes description, "\\n\\n#{url}", "the page link, after an escaped blank line"
    assert_equal "cyvasse-night-2026-10-06.ics", @night.ics_filename
  end

  test "a long line folds without splitting a multibyte character" do
    folded = @night.send(:fold, "DESCRIPTION:#{'é' * 60}")

    assert(folded.split("\r\n").all? { |line| line.bytesize <= 75 && line.valid_encoding? })
    assert_equal "DESCRIPTION:#{'é' * 60}", folded.gsub("\r\n ", "")
  end

  test "the Google Calendar link carries the UTC window, the zone and the page" do
    uri = URI(@night.google_calendar_url("https://cyvasse.xyz/night"))
    query = Rack::Utils.parse_query(uri.query)

    assert_equal "calendar.google.com", uri.host
    assert_equal "TEMPLATE", query["action"]
    assert_equal "Cyvasse Night", query["text"]
    assert_equal "20261007T010000Z/20261007T040000Z", query["dates"]
    assert_equal "America/Denver", query["ctz"]
    assert_equal "https://cyvasse.xyz/night", query["location"]
    assert query["details"].end_with?("https://cyvasse.xyz/night")
  end

  test "the Event JSON-LD is an online event at the page, starting and ending on the hour in Mountain time" do
    data = @night.json_ld(page_url: "https://cyvasse.xyz/night", image: "https://cyvasse.xyz/og.png",
                          site_url: "https://cyvasse.xyz/")

    assert_equal "Event", data["@type"]
    assert_equal "2026-10-06T19:00:00-06:00", data["startDate"]
    assert_equal "2026-10-06T22:00:00-06:00", data["endDate"]
    assert_equal "https://schema.org/OnlineEventAttendanceMode", data["eventAttendanceMode"]
    assert_equal "https://schema.org/EventScheduled", data["eventStatus"]
    assert_equal({ "@type" => "VirtualLocation", "url" => "https://cyvasse.xyz/night" }, data["location"])
    assert_equal "Cyvasse Night: Tuesday, October 6", data["name"]
    assert_equal [ "Offer", "0" ], data["offers"].values_at("@type", "price")
    assert_equal [ "https://cyvasse.xyz/og.png" ], data["image"]
  end

  test "players online: a live search or a human seat in a live match that moved in the last five minutes" do
    now = Time.current
    searcher = player("searcher")
    LiveSeek.create!(user: searcher, last_seen_at: now - 1.second)
    stale = player("stale")
    LiveSeek.create!(user: stale, last_seen_at: now - 10.minutes)
    arya = player("arya")
    sansa = player("sansa")
    live_match(arya, sansa, updated_at: now - 2.minutes)
    jon = player("jon")
    live_match(jon, computer, updated_at: now - 1.minute, away_bot: true)
    idle = player("idle")
    live_match(idle, player("idle2"), updated_at: now - 20.minutes)
    turn_based = player("turnbased")
    Match.create!(home_user: turn_based, away_user: player("friend"), match_status: Match::IN_PROGRESS,
                  match_against: "human", live: false)

    presence = CyvasseNight.count_presence(now)

    assert_equal 4, presence.online, "searcher, arya, sansa, jon: not the stale search, the idle match, the computer or a turn-based game"
    assert_equal 1, presence.searching, "only the search still polling and unmatched"
  end

  test "a player searching and playing is one player online" do
    now = Time.current
    arya = player("arya")
    live_match(arya, computer, updated_at: now, away_bot: true)
    LiveSeek.create!(user: arya, last_seen_at: now)

    assert_equal 1, CyvasseNight.count_presence(now).online
  end

  test "tonight's leaderboard counts only the live games finished inside the window" do
    arya = player("arya")
    sansa = player("sansa")
    live_result(arya, sansa, winner: arya, finished_at: @night.starts_at - 1.minute)
    live_result(sansa, arya, winner: sansa, finished_at: @night.starts_at + 1.hour)
    live_result(sansa, arya, winner: sansa, finished_at: @night.starts_at + 2.hours)
    live_result(arya, sansa, winner: arya, finished_at: @night.ends_at)

    rows = @night.leaderboard

    assert_equal %w[sansa arya], rows.map { |row| row.user.username }
    assert_equal [ 2, 2 ], rows.map(&:games)
    assert_equal [ 2, 0 ], rows.map(&:wins)
    assert_equal [ 6, 2 ], rows.map(&:points)
    assert_equal [ 4, 4 ], Leaderboard.live.map(&:games), "the live board still counts every game"
  end

  private

  def live_match(home, away, updated_at:, **attrs)
    match = Match.create!(home_user: home, away_user: away, live: true, match_status: Match::IN_PROGRESS,
                          match_against: "human", home_ready: true, away_ready: true, turn: 3, **attrs)
    match.update_columns(updated_at:)
    match
  end
end
