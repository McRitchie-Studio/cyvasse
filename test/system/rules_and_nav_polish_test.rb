require "application_system_test_case"

# [e2e] Production UX audit #2 (task cyvasse-rules-and-nav-polish), measured in
# the browser:
# - #3: the board key opens inside the screen on a phone: the match page at
#   390x844, where its "?" sits in the timer card below the board, and /play
#   held sideways at 844x390. It ran 118px and 21px off the bottom.
# - #11: a rule link on /rules at 375x667 lands its card below the navbar,
#   which covered 22px of it.
# - #14: the navbar's Leaderboard badge takes the new rank when a game ends,
#   without a page load.
# SCREENSHOTS=1 saves each view to tmp/screenshots/polish2-*.png.
class RulesAndNavPolishTest < ApplicationSystemTestCase
  include MatchPlay

  # The key panel's box against the screen and the navbar, once it is open.
  PANEL_JS = <<~JS.freeze
    ((details) => {
      const panel = details.querySelector(".cyvasse-legend-panel").getBoundingClientRect()
      const nav = document.querySelector("header[data-pin=nav]").getBoundingClientRect()
      return { top: panel.top, bottom: panel.bottom, left: panel.left, right: panel.right,
               navBottom: nav.bottom, height: document.documentElement.clientHeight,
               width: document.documentElement.clientWidth, placement: details.dataset.placement || null }
    })(arguments[0])
  JS

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "390x844: the match page's board key opens inside the screen" do
    arya = make_player("arya")
    match = Match.start_live!(arya, computer: true, rng: Random.new(4))
    match.set_up!(arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    sign_in(arya)

    phone(390, 844)
    visit match_path(match)
    assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10
    assert_controllers_connected("board-key")
    key = find(".match-panel-status details.cyvasse-legend")

    # The "?" at the bottom of the screen, as a player scrolls to it.
    page.execute_script("arguments[0].scrollIntoView({ block: 'end' })", key)
    key.find("summary").click
    assert_selector ".match-panel-status details.cyvasse-legend[open][data-placement]"
    box = page.evaluate_script(PANEL_JS, key)
    screenshot("key-match-390")
    assert_inside box, "the match page's key at 390x844"
    assert_equal "above", box["placement"], "no room under the timer card, so it opens over the board"
  end

  test "844x390: the /play board key opens inside the screen" do
    phone(844, 390)
    visit play_path
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play]", wait: 15
    assert_controllers_connected("board-key")

    key = find(".cyvasse-board-bar details.cyvasse-legend")
    page.execute_script("arguments[0].scrollIntoView({ block: 'end' })", key)
    key.find("summary").click
    assert_selector ".cyvasse-board-bar details.cyvasse-legend[open][data-placement]"
    box = page.evaluate_script(PANEL_JS, key)
    screenshot("key-play-844")
    assert_inside box, "the /play key at 844x390"

    # Every entry can still be read: a capped panel scrolls inside itself.
    reach = page.evaluate_script(<<~JS, key)
      ((details) => {
        const panel = details.querySelector(".cyvasse-legend-panel")
        panel.scrollTop = panel.scrollHeight
        const last = [...panel.querySelectorAll(".cyvasse-legend-entry")].pop().getBoundingClientRect()
        const box = panel.getBoundingClientRect()
        return last.bottom <= box.bottom + 1 && last.top >= box.top - 1
      })(arguments[0])
    JS
    assert reach, "the last entry scrolls into the panel"
  end

  test "375x667: a rule link lands its card below the navbar" do
    phone(375, 667)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit rules_path
    assert_controllers_connected("rule-links")

    link = find("#unit-rabble dd[data-stat=trump] a[href='#rule-trumps']")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", link)
    link.click
    assert_equal "#rule-trumps", page.evaluate_script("location.hash")
    gap = settled_gap("#rule-trumps")
    screenshot("rule-link-375")
    assert_operator gap, :>=, 0, "the Trumps card starts #{gap.round}px below the navbar's bottom edge"

    # A deep link from anywhere lands the same way.
    visit "#{rules_path}#rule-range"
    assert_operator settled_gap("#rule-range"), :>=, 0, "a deep link to the Range card clears the navbar"
  end

  test "the navbar's rank badge takes the new rank when the game ends" do
    arya = make_player("arya")
    match = Match.start_live!(arya, computer: true, rng: Random.new(4))
    match.set_up!(arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    sign_in(arya)
    visit match_path(match)
    assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10
    assert_nil Leaderboard.rank_for(arya), "arya starts off the board"
    assert_equal [ nil, nil ], badges, "no badge before the game counts"

    match.reload.send(:finish!, winner: arya, reason: "forfeit")
    assert_selector "[data-test=game-over-modal]", wait: 10
    rank = "##{Leaderboard.rank_for(arya).rank}"
    assert_equal [ rank, rank ], badges, "both rows show the new rank without a page load"
    screenshot("nav-rank")

    visit match_path(match)
    assert_equal [ rank, rank ], badges, "the server draws the same badge on the next load"
  end

  private

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.player_name}"
  end

  def phone(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: true)
  end

  # The badge text in each Leaderboard link of the navbar (the desktop bar,
  # then the phone row), nil where there is none.
  def badges
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll("header[data-pin=nav] nav[aria-label=Main] a[href='/leaderboard']")]
        .map((a) => a.querySelector("span")?.textContent.trim() || null)
    JS
  end

  # The card's top less the navbar's bottom, once the navbar's collapse and
  # the scroll have both come to rest (three frames running unchanged).
  def settled_gap(selector)
    page.evaluate_async_script(<<~JS, selector)
      const [selector, done] = arguments
      let last = null, still = 0, frames = 0
      const read = () => document.querySelector(selector).getBoundingClientRect().top -
        document.querySelector("header[data-pin=nav]").getBoundingClientRect().bottom
      const tick = () => {
        const gap = read()
        still = gap === last ? still + 1 : 0
        last = gap
        if (still >= 3 || ++frames > 240) done(gap)
        else requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
    JS
  end

  def assert_inside(box, label)
    assert_operator box["bottom"], :<=, box["height"], "#{label}: bottom #{box["bottom"].round}px on a #{box["height"]}px screen"
    assert_operator box["top"], :>=, box["navBottom"], "#{label}: top #{box["top"].round}px under the navbar (#{box["navBottom"].round}px)"
    assert_operator box["left"], :>=, 0, "#{label}: left edge"
    assert_operator box["right"], :<=, box["width"], "#{label}: right edge"
  end

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    page.save_screenshot(Rails.root.join("tmp/screenshots/polish2-#{name}.png"))
  end
end
