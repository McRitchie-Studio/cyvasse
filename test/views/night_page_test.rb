require "test_helper"

# [component] Cyvasse Night's partials rendered alone (task
# cyvasse-night-event-page): the home hero's banner, shown until the night is
# over, and the countdown helper's first paint.
class NightPageViewTest < ActionView::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include NightsHelper

  setup { @night = CyvasseNight.current }

  test "the banner links to /night with the short date and time before the night" do
    travel_to(@night.starts_at - 1.day) { render "nights/home_banner", night: @night }

    assert_select "a.night-home-banner[href=?][data-night-banner]", night_path, 1
    assert_select "a.night-home-banner", /Cyvasse Night · Tue Oct 6, 7 PM MT/
    assert_select "a.night-home-banner span[aria-hidden=true]", "→"
  end

  test "the banner says the night is live while it runs" do
    travel_to(@night.starts_at + 1.minute) { render "nights/home_banner", night: @night }

    assert_select "a.night-home-banner", /Live now/
  end

  test "the banner is gone once the night is over" do
    travel_to(@night.ends_at) { render "nights/home_banner", night: @night }

    assert_select "a.night-home-banner", 0
  end

  test "the countdown's first paint splits the time left, never negative" do
    now = @night.starts_at - (1.day + 2.hours + 3.minutes + 4.5.seconds)

    assert_equal({ days: 1, hours: 2, minutes: 3, seconds: 5 }, night_countdown_parts(@night.starts_at, now))
    assert_equal({ days: 0, hours: 0, minutes: 0, seconds: 0 }, night_countdown_parts(@night.starts_at, @night.ends_at))
  end

  test "the presence line counts players, singular and plural" do
    assert_equal "<strong>1 player</strong> online · <strong>0</strong> searching now",
                 night_presence_line(CyvasseNight::Presence.new(online: 1, searching: 0))
    assert_match(/3 players/, night_presence_line(CyvasseNight::Presence.new(online: 3, searching: 2)))
  end
end
