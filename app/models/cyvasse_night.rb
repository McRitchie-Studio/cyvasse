# Cyvasse Night (task cyvasse-night-event-page): a scheduled evening when
# everyone plays live at once, so Play Now (LiveSeek) pairs people with
# people instead of computer players. /night announces it, counts down to it,
# carries Play Now while it runs and tonight's leaderboard during and after.
#
# THE NEXT NIGHT IS ONE LINE: change NEXT. Everything else, the page's three
# states, the home banner, the calendar file, the Google Calendar link, the
# SEO copy and the Event JSON-LD, reads it from here.
#
# The window is [starts_at, ends_at): at 7:00 PM exactly the night is on, at
# 10:00 PM exactly it is over.
class CyvasseNight
  ZONE = "America/Denver".freeze
  NEXT = Time.find_zone(ZONE).parse("2026-10-06 19:00")
  DURATION = 3.hours

  # "Players online": a Play Now search still polling, or a human seat in a
  # live match that moved, within the last PRESENCE_WINDOW. Counted at most
  # once per PRESENCE_CACHE, so a full page of visitors costs one query.
  PRESENCE_WINDOW = 5.minutes
  PRESENCE_CACHE = 30.seconds
  PRESENCE_CACHE_KEY = "cyvasse_night/presence".freeze

  PHASES = %i[before during after].freeze
  TITLE = "Cyvasse Night".freeze

  Presence = Data.define(:online, :searching)

  attr_reader :starts_at, :ends_at

  def self.current = new

  def initialize(starts_at: NEXT, duration: DURATION)
    @starts_at = starts_at.in_time_zone(ZONE)
    @ends_at = @starts_at + duration
  end

  def phase(now = Time.current)
    if now < starts_at then :before
    elsif now < ends_at then :during
    else :after
    end
  end

  def before?(now = Time.current) = phase(now) == :before
  def during?(now = Time.current) = phase(now) == :during
  def after?(now = Time.current) = phase(now) == :after

  # The home page's banner: up until the night is over.
  def banner?(now = Time.current) = now < ends_at

  # The live games that count for tonight's leaderboard.
  def window = starts_at...ends_at

  # "Tuesday, October 6"
  def date_label = starts_at.strftime("%A, %B %-d")

  # "Tue Oct 6"
  def short_date_label = starts_at.strftime("%a %b %-d")

  # "7 PM Mountain"; "7:30 PM Mountain" when not on the hour.
  def time_label = "#{clock(starts_at)} Mountain"

  # "7 PM MT"
  def short_time_label = "#{clock(starts_at)} MT"

  # "7–10 PM Mountain"
  def window_label = "#{clock(starts_at, meridian: false)}–#{clock(ends_at)} Mountain"

  # Tonight's live leaderboard: live games finished inside the window.
  def leaderboard(limit: Leaderboard::LIVE_SIZE) = Leaderboard.live(limit:, within: window)

  # How many people are here and how many are searching, cached briefly.
  def self.presence(now: Time.current)
    Rails.cache.fetch(PRESENCE_CACHE_KEY, expires_in: PRESENCE_CACHE) { count_presence(now) }
  end

  def self.count_presence(now = Time.current)
    since = now - PRESENCE_WINDOW
    seekers = LiveSeek.where(last_seen_at: since..).select(:user_id)
    playing = Match.live.active.where(updated_at: since..)
    home = playing.where(home_bot: false).select(:home_user_id)
    away = playing.where(away_bot: false).select(:away_user_id)
    online = User.where(id: seekers).or(User.where(id: home)).or(User.where(id: away)).count
    searching = LiveSeek.open.where(last_seen_at: (now - LiveSeek::ALIVE)..).distinct.count(:user_id)
    Presence.new(online:, searching:)
  end

  def description
    "Everyone plays live at once: come at #{clock(starts_at)} Mountain, press Play Now and get matched " \
      "against other players, then climb tonight's leaderboard."
  end

  # A Google Calendar "add event" link for the night.
  def google_calendar_url(page_url)
    query = { action: "TEMPLATE", text: TITLE,
              dates: "#{utc_stamp(starts_at)}/#{utc_stamp(ends_at)}",
              details: "#{description}\n\n#{page_url}", location: page_url, ctz: ZONE }
    "https://calendar.google.com/calendar/render?#{query.to_query}"
  end

  # The night as an iCalendar file (RFC 5545), for "Add to calendar". Times
  # are UTC, so no VTIMEZONE block is needed; lines end in CRLF and fold at
  # 75 octets, as the RFC requires.
  def to_ics(page_url, now: Time.current)
    lines = [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Cyvasse//Cyvasse Night//EN",
      "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:cyvasse-night-#{starts_at.utc.strftime('%Y%m%d')}@cyvasse.xyz",
      "DTSTAMP:#{utc_stamp(now)}",
      "DTSTART:#{utc_stamp(starts_at)}",
      "DTEND:#{utc_stamp(ends_at)}",
      "SUMMARY:#{ics_text(TITLE)}",
      "DESCRIPTION:#{ics_text("#{description}\n\n#{page_url}")}",
      "LOCATION:#{ics_text(page_url)}",
      "URL:#{page_url}",
      "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:#{ics_text("#{TITLE} starts in 15 minutes")}",
      "TRIGGER:-PT15M", "END:VALARM",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    lines.map { |line| fold(line) }.join("\r\n") + "\r\n"
  end

  def ics_filename = "cyvasse-night-#{starts_at.strftime('%Y-%m-%d')}.ics"

  # schema.org Event, for search results' event listings.
  def json_ld(page_url:, image:, site_url:)
    { "@context" => "https://schema.org", "@type" => "Event",
      "name" => "#{TITLE}: #{date_label}", "description" => description,
      "startDate" => starts_at.iso8601, "endDate" => ends_at.iso8601,
      "eventStatus" => "https://schema.org/EventScheduled",
      "eventAttendanceMode" => "https://schema.org/OnlineEventAttendanceMode",
      "location" => { "@type" => "VirtualLocation", "url" => page_url },
      "image" => [ image ], "url" => page_url, "isAccessibleForFree" => true,
      "organizer" => { "@type" => "Organization", "name" => "Cyvasse", "url" => site_url },
      "offers" => { "@type" => "Offer", "price" => "0", "priceCurrency" => "USD",
                    "availability" => "https://schema.org/InStock", "url" => page_url,
                    "validFrom" => SeoPage::CONTENT_UPDATED.iso8601 } }
  end

  private

  def clock(time, meridian: true)
    format = time.min.zero? ? "%-l" : "%-l:%M"
    time.strftime(meridian ? "#{format} %p" : format)
  end

  def utc_stamp(time) = time.utc.strftime("%Y%m%dT%H%M%SZ")

  # RFC 5545 TEXT: escape backslash, semicolon, comma and newline.
  def ics_text(text)
    text.gsub("\\") { "\\\\" }.gsub(";", "\\;").gsub(",", "\\,").gsub(/\r?\n/, "\\n")
  end

  # Fold a content line longer than 75 octets: CRLF plus one space before each
  # continuation, never splitting a multibyte character.
  def fold(line)
    return line if line.bytesize <= 75

    chunks = []
    current = +""
    line.each_char do |char|
      limit = chunks.empty? ? 75 : 74
      if current.bytesize + char.bytesize > limit
        chunks << current
        current = +""
      end
      current << char
    end
    chunks << current
    chunks.join("\r\n ")
  end
end
