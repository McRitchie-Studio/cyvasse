require "test_helper"

# [component] The navbar collapses on the scroll timeline from 768px
# (config.navbar_scroll_timeline, studio-engine 0.111; task
# scroll-timeline-navbar-rollout). The collapse itself is computed style on a
# scroll timeline, settled in a browser; what a page can show is that the
# header opted in and still carries the engine's controller, which runs the
# timeline from 768px and the --nav-p collapse on a phone.
class NavbarScrollTimelineTest < ActionDispatch::IntegrationTest
  test "the header opts into the scroll-driven collapse, signed out and signed in" do
    get root_path
    assert_response :success
    assert_select "header.nav-shell[data-pin=nav][data-nav-timeline][data-studio-controller=nav-collapse]", 1

    guest = User.create_guest!(rng: Random.new(11))
    guest.update!(email: "guest-timeline@example.com")
    log_in_as(guest)
    get root_path
    assert_select "header.nav-shell[data-nav-timeline][data-studio-controller=nav-collapse]", 1
  end
end
