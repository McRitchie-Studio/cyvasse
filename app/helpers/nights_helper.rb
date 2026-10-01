# Cyvasse Night's page (nights/show) and the home page's banner to it.
module NightsHelper
  # The countdown's first paint, before its controller ticks: days, hours,
  # minutes and seconds to `target`, as night_clock.js counts them.
  def night_countdown_parts(target, now = Time.current)
    left = [ (target - now).ceil, 0 ].max
    days, left = left.divmod(86_400)
    hours, left = left.divmod(3600)
    minutes, seconds = left.divmod(60)
    { days:, hours:, minutes:, seconds: }
  end

  # "3 players online · 1 searching now"
  def night_presence_line(presence)
    online = pluralize(presence.online, "player")
    safe_join([ tag.strong(online), " online", " · ", tag.strong(presence.searching.to_s), " searching now" ])
  end

  def night_google_calendar_url(night)
    night.google_calendar_url(seo_absolute_url(night_path))
  end
end
