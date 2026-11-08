require "application_system_test_case"

# [e2e] Task cyvasse-standard-page-headers: the engine page header in a real
# browser, at the desktop size and on a 390px phone (Chrome's device emulation:
# a desktop window will not shrink that far). On a desktop the crumb trail
# shows; on a phone it gives way to one link to the parent, the leaderboard's
# tabs stay on screen, and no page scrolls sideways. Once the visitor scrolls,
# the row sticks under the navbar.
class PageHeaderTest < ApplicationSystemTestCase
  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  def phone!(width = 390)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 844, deviceScaleFactor: 1, mobile: true)
  end

  def assert_no_sideways_scroll(label)
    scroll, client = page_widths
    assert_operator scroll, :<=, client, "no sideways scroll: #{label}"
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as"
  end

  test "the privacy page header at desktop and 390px, and it sticks under the navbar" do
    visit privacy_path
    within(".page-header") do
      assert_selector "h1.page-header-title", text: "Privacy Policy"
      assert_selector "nav.page-header-crumbs a.page-header-crumb", text: "Home", visible: true
      assert_no_selector "a.page-header-parent", visible: true
    end
    assert_no_sideways_scroll "privacy at desktop"

    phone!
    visit privacy_path
    within(".page-header") do
      assert_selector "h1.page-header-title", visible: true
      assert_selector "a.page-header-parent", text: "Home", visible: true
      assert_no_selector "nav.page-header-crumbs", visible: true
    end
    assert_no_sideways_scroll "privacy at 390px"

    # The navbar collapses as the page scrolls, and the pinned stack republishes
    # --pin-page-top once it settles, so the check waits for the stack to settle.
    execute_script("window.scrollTo(0, 1500)")
    gap = -> { evaluate_script(<<~JS) }
      Math.abs(Math.round(document.querySelector('.page-header').getBoundingClientRect().top -
                          document.querySelector('header[data-pin=nav]').getBoundingClientRect().bottom))
    JS
    page.document.synchronize(5) { raise Capybara::ExpectationNotMet, "row #{gap.call}px off the navbar" if gap.call > 2 }
    assert_operator gap.call, :<=, 2, "the row sticks under the navbar"
  end

  test "the leaderboard's tabs switch boards from the header, on a 390px phone" do
    phone!
    visit leaderboard_path
    within(".page-header") do
      assert_selector "a.page-header-tab[aria-current=page]", text: "Live", visible: true
      click_on "All-time"
    end
    assert_selector "[data-board=all-time]"
    assert_selector ".page-header a.page-header-tab[aria-current=page]", text: "All-time", visible: true
    assert_no_sideways_scroll "leaderboard at 390px"
  end

  test "an admin walks from a match back to Conversations by the header, on a 390px phone" do
    admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin")
    arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne_of_tarth_xx")
    match = Match.challenge!(arya, "brienne_of_tarth_xx")
    sign_in(admin)

    phone!
    visit admin_match_path(match)
    assert_selector ".page-header h1", text: "Match ##{match.id}: arya vs brienne_of_tarth_xx"
    assert_no_sideways_scroll "admin match at 390px"
    find(".page-header a.page-header-parent", text: "Conversations").click
    assert_selector ".page-header h1", text: "Conversations"
    assert_selector ".page-header nav.page-header-links a", text: "Message Board", visible: true
    assert_no_sideways_scroll "admin conversations at 390px"
  end
end
