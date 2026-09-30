require "application_system_test_case"

# [e2e] Setup layouts for phones on their side and tablets (task
# cyvasse-dock-landscape-tablet). The phone dock (phone_setup_dock_test)
# covers phones held upright; here the other touch screens keep the board and
# the whole army card, Smart Setup and Ready with it, on the screen together
# for the whole setup:
#
# - a phone on its side (844x390, 932x430): the card is a sheet at the
#   screen's right, beside a board sized to the screen's height;
# - a tablet held upright (820x1180): the bottom sheet, with wider tiles;
# - a tablet on its side (1180x820): the desktop's two columns, the board
#   capped so the card stays on the screen beside it.
#
# At each size, when setup opens and after every pick and placement, the
# board sits under the pinned navbar and on the screen, the card is wholly on
# the screen and clear of the board, placing all 19 never scrolls the page,
# and nothing scrolls sideways. On a live match the sheet carries the clock.
#
# Touch is emulated, as on the real devices: it is what tells a tablet from a
# desktop of the same width. Reduced motion is on, so the one scroll a pick
# makes lands at once. DOCK_LT_SHOTS=<dir> saves each size as dock-lt-*.png.
class SetupLayoutFitTest < ApplicationSystemTestCase
  include MatchPlay

  SIZES = [
    [ "phone-landscape-844x390", 844, 390, "side" ],
    [ "phone-landscape-932x430", 932, 430, "side" ],
    [ "tablet-portrait-820x1180", 820, 1180, "bottom" ],
    [ "tablet-landscape-1180x820", 1180, 820, "page" ]
  ].freeze

  teardown do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  SIZES.each do |label, width, height, fit|
    test "/play places a whole army at #{width}x#{height} with the board and the army card both in view" do
      touch_screen!(width, height)
      visit play_path
      assert_controllers_connected "cyvasse-game"
      place_the_army("play-#{label}", fit)
    end

    test "a live match places a whole army at #{width}x#{height} with the board and the army card both in view" do
      arya = make_player("arya")
      match = Match.start_live!(arya, computer: true, rng: Random.new(4))
      sign_in(arya)
      touch_screen!(width, height)
      visit match_path(match)
      assert_controllers_connected "cyvasse-match"
      clock = fit == "page" ? ".live-clock-seconds" : ".cyvasse-army .cyvasse-army-clock"
      assert_selector clock, text: /\A\d+s\z/
      place_the_army("match-#{label}", fit)
      find_button("Ready").click
      assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10
      assert_no_selector ".cyvasse-army", visible: :visible
    end
  end

  test "a desktop of a tablet's size keeps its layout: no fit, no scroll at a pick" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: 1180, height: 820, deviceScaleFactor: 1, mobile: false)
    visit play_path
    assert_controllers_connected "cyvasse-game"
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_equal "", page.evaluate_script(%(getComputedStyle(document.querySelector(".cyvasse-game")).getPropertyValue("--setup-fit").trim()))
    assert_equal "static", find(".cyvasse-army").style("position")["position"]
    find(".cyvasse-dock .dock-unit", match: :first).click
    assert_selector "svg.cyvasse-board g.hex.is-drop", minimum: 1
    assert_equal 0, page.evaluate_script("window.scrollY"), "a desktop pick does not scroll"
  end

  private

  def place_the_army(label, fit)
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_equal fit, page.evaluate_script(%(getComputedStyle(document.querySelector(".cyvasse-game")).getPropertyValue("--setup-fit").trim()))
    assert_equal(fit == "page" ? "static" : "fixed", find(".cyvasse-army").style("position")["position"])

    # The opening scroll runs a frame after the first render.
    opened = settle { |box| fits?(box) }
    assert_both_in_view opened, "when setup opens"
    shot("#{label}-0-open")

    find(".cyvasse-dock .dock-unit", match: :first).click
    assert_selector "svg.cyvasse-board g.hex.is-drop", minimum: 1
    settled = settle { |box| fits?(box) }
    assert_both_in_view settled, "after the first pick"
    shot("#{label}-1-picked")

    19.times do |n|
      find(".cyvasse-dock .dock-unit", match: :first).click unless n.zero?
      find("svg.cyvasse-board g.hex.is-drop", match: :first).click
      assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='1']", count: n + 1
      now = in_view
      assert_in_delta settled["scrollY"], now["scrollY"], 1, "placing unit #{n + 1} scrolled the page"
      assert_both_in_view now, "after placing unit #{n + 1}"
    end

    assert_no_selector ".cyvasse-dock .dock-unit"
    assert_button "Ready", disabled: false
    assert_both_in_view in_view, "with the army placed"
    scroll, client = page_widths
    assert_operator scroll, :<=, client, "no sideways scroll"
    shot("#{label}-2-placed")
  end

  def fits?(box)
    box["board"]["top"] >= box["pinned"] - 1 && box["board"]["bottom"] <= box["viewport"]["height"] + 1 &&
      box["army"]["top"] >= box["pinned"] - 1 && box["army"]["bottom"] <= box["viewport"]["height"] + 1
  end

  # Waits for the board and the card to fit and the page to hold still for
  # half a second: a pick's scroll collapses the navbar, and the controller's
  # re-check pass (300ms on) may still move the page.
  def settle(seconds = 4)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    box = in_view
    still_since = nil
    loop do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if now > deadline

      sleep 0.05
      last = box
      box = in_view
      if yield(box) && (box["scrollY"] - last["scrollY"]).abs < 0.5 && box["pinned"] == last["pinned"]
        still_since ||= now
        break if now - still_since >= 0.5
      else
        still_since = nil
      end
    end
    box
  end

  def assert_both_in_view(box, moment)
    view = box["viewport"]
    board = box["board"]
    army = box["army"]
    ready = box["ready"]
    assert_operator board["top"], :>=, box["pinned"] - 1, "#{moment}: the board's top is under the navbar"
    assert_operator board["bottom"], :<=, view["height"] + 1, "#{moment}: the board runs off the screen's foot"
    assert_operator board["left"], :>=, -1, "#{moment}: the board runs off the screen's left"
    assert_operator board["right"], :<=, view["width"] + 1, "#{moment}: the board runs off the screen's right"
    assert_operator army["top"], :>=, box["pinned"] - 1, "#{moment}: the army card's top is under the navbar"
    assert_operator army["bottom"], :<=, view["height"] + 1, "#{moment}: the army card runs off the screen's foot"
    assert_operator army["left"], :>=, -1, "#{moment}: the army card runs off the screen's left"
    assert_operator army["right"], :<=, view["width"] + 1, "#{moment}: the army card runs off the screen's right"
    overlap = [ board["right"], army["right"] ].min - [ board["left"], army["left"] ].max > 1 &&
              [ board["bottom"], army["bottom"] ].min - [ board["top"], army["top"] ].max > 1
    refute overlap, "#{moment}: the army card covers the board #{box.inspect}"
    assert_operator ready["top"], :>=, army["top"] - 1, "#{moment}: Ready is in the army card"
    assert_operator ready["bottom"], :<=, army["bottom"] + 1, "#{moment}: Ready is in the army card"
    assert_equal 0, box["armyScroll"], "#{moment}: the army card needs no scrolling of its own"
  end

  def in_view
    page.evaluate_script(<<~JS)
      (() => {
        const box = (selector) => {
          const r = document.querySelector(selector).getBoundingClientRect()
          return { top: r.top, bottom: r.bottom, left: r.left, right: r.right }
        }
        const army = document.querySelector(".cyvasse-army")
        const pinned = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--pin-stack-bottom")) || 0
        return { scrollY: window.scrollY, viewport: { width: window.innerWidth, height: window.innerHeight }, pinned,
                 board: box("svg.cyvasse-board"), army: box(".cyvasse-army"), ready: box(".cyvasse-ready"),
                 armyScroll: Math.max(0, army.scrollHeight - army.clientHeight) }
      })()
    JS
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.player_name}"
  end

  def touch_screen!(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height:, deviceScaleFactor: 2, mobile: true)
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 5)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
                                    features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
  end

  def shot(name)
    dir = ENV["DOCK_LT_SHOTS"]
    return unless dir

    FileUtils.mkdir_p(dir)
    page.save_screenshot(File.join(dir, "dock-lt-#{name}.png"))
  end
end
