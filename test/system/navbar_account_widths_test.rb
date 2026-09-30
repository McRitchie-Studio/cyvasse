require "application_system_test_case"

# [e2e] The navbar as studio-engine renders it, with no Cyvasse copy of
# components/_user_nav (0.80.0; task cyvasse-navbar-config-switch), in a real
# browser, in the light theme and the dark. At 390px: one theme toggle, and
# the account link is the avatar alone, the name a clipped screen-reader box.
# At 1440px: one theme toggle, the desktop link-sidebar button (the engine's
# extra_icons_html), and the account link with the player's public name
# beside the avatar, truncated when long. Signed out, both widths say
# "Sign in". SCREENSHOTS=1 saves each view to
# tmp/screenshots/navbar-config-<width>-<theme>.png.
class NavbarAccountWidthsSystemTest < ApplicationSystemTestCase
  NAV = "header[data-pin=nav]".freeze

  setup do
    @guest = User.create_guest!(rng: Random.new(21))
    @guest.update!(email: "navbar-widths@example.com")
    visit link_path(token: Studio::Link.create_magic_link(email: @guest.email).token)
    assert_text "Signed in as #{@guest.player_name}"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.execute_script("try { localStorage.removeItem('theme') } catch (e) {}")
  end

  %w[light dark].each do |theme|
    test "#{theme}, 390px: one theme toggle and the avatar alone as the account link" do
      at_width(390, mobile: true)
      visit_in_theme(root_path, theme)

      assert_selector "#{NAV} button[title='Toggle theme']", visible: true, count: 1
      assert_selector "#{NAV} a[data-nav-account]", visible: true, count: 1
      assert_selector "#{NAV} a[data-nav-account] [aria-hidden=true]", visible: true
      width = page.evaluate_script("document.querySelector('#{NAV} [data-nav-name]').parentElement.getBoundingClientRect().width")
      assert_operator width, :<=, 1, "the name takes no room on a phone"
      screenshot("390-#{theme}")
    end

    test "#{theme}, 1440px: one theme toggle, the sidebar button, and the name beside the avatar" do
      at_width(1440, mobile: false)
      visit_in_theme(root_path, theme)

      assert_selector "#{NAV} button[title='Toggle theme']", visible: true, count: 1
      assert_selector "#{NAV} [data-link-sidebar-trigger]", visible: true, count: 1
      assert_selector "#{NAV} a[data-nav-account]", visible: true, count: 1
      assert_selector "#{NAV} a[data-nav-account] [data-nav-name]", visible: true, text: @guest.player_name
      screenshot("1440-#{theme}")
    end
  end

  test "1440px: a long name truncates inside its box and the avatar stays whole" do
    @guest.update!(username: "W" * 20)
    at_width(1440, mobile: false)
    visit root_path

    name = find("#{NAV} a[data-nav-account] [data-nav-name]", visible: true, text: "W" * 20)
    box = page.evaluate_script(<<~JS, name)
      ((el) => ({ scroll: el.scrollWidth, client: el.clientWidth,
                  overflow: getComputedStyle(el).textOverflow,
                  box: el.parentElement.getBoundingClientRect().width }))(arguments[0])
    JS
    assert_operator box["scroll"], :>, box["client"], "twenty W's overflow the name box"
    assert_equal "ellipsis", box["overflow"]
    assert_operator box["box"], :<=, 160, "md:max-w-40 caps the name at 10rem"
    avatar = page.evaluate_script("document.querySelector('#{NAV} a[data-nav-account] [aria-hidden=true]').getBoundingClientRect().right")
    assert_operator avatar, :<=, 1440, "the avatar stays on screen"
    screenshot("1440-long-name")
  end

  [ 390, 1440 ].each do |width|
    test "#{width}px signed out: the navbar says Sign in, never Log in" do
      visit logout_path if respond_to?(:logout_path)
      Capybara.reset_sessions!
      at_width(width, mobile: width < 768)
      visit root_path

      assert_selector "#{NAV} a", text: "Sign in", visible: true, minimum: 1
      assert_no_selector "#{NAV} a", text: /\bLog ?in\b/, visible: true
      assert_selector "#{NAV} button[title='Toggle theme']", visible: true, count: 1
      screenshot("#{width}-signed-out")
    end
  end

  private

  def at_width(width, mobile:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 900, deviceScaleFactor: 1, mobile: mobile)
  end

  def visit_in_theme(path, theme)
    visit path
    page.execute_script("localStorage.setItem('theme', arguments[0])", theme)
    visit path
    assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/navbar-config-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
