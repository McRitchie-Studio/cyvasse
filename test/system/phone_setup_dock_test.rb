require "application_system_test_case"

# [e2e] The phone setup dock (task cyvasse-phone-setup-dock). On a phone the
# army card once followed the board, so each of the 19 units meant scrolling
# down to pick it and up to place it, on a running clock. During setup it
# is now a sheet fixed to the bottom of the screen:
#
# - when setup opens, before any pick, the whole board (the player's own
#   rows at its bottom included) sits above the sheet;
# - after a unit is picked, the whole board and the whole sheet are on the
#   screen at once, the board above the sheet;
# - placing all 19 needs no page scroll, and Ready is on the screen;
# - on a live match the sheet carries the setup clock;
# - the desktop card stays in the sidebar, in the page's flow.
#
# Reduced motion is on, so the one scroll a pick makes lands at once.
# PHONE_DOCK_SHOTS=<dir> saves each size as phone-dock-*.png there.
class PhoneSetupDockTest < ApplicationSystemTestCase
  include MatchPlay

  SIZES = [ [ 390, 844 ], [ 375, 667 ] ].freeze

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  SIZES.each do |width, height|
    test "/play places a whole army at #{width}x#{height} with the board and the dock both in view" do
      phone!(width, height)
      visit play_path
      assert_controllers_connected "cyvasse-game"
      place_the_army("play-#{width}x#{height}")
    end

    test "a live match places a whole army at #{width}x#{height} with the board and the dock both in view" do
      arya = make_player("arya")
      match = Match.start_live!(arya, computer: true, rng: Random.new(4))
      sign_in(arya)
      phone!(width, height)
      visit match_path(match)
      assert_controllers_connected "cyvasse-match"
      assert_selector ".cyvasse-army .cyvasse-army-clock", text: /\A\d+s\z/
      place_the_army("match-#{width}x#{height}")
      find_button("Ready").click
      assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10
      assert_no_selector ".cyvasse-army", visible: :visible
    end
  end

  test "the desktop army card stays in the sidebar" do
    visit play_path
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_equal "static", find(".cyvasse-army").style("position")["position"]
    assert_selector ".cyvasse-army-clock", visible: :hidden
    layout = page.evaluate_script(<<~JS)
      (() => {
        const board = document.querySelector("svg.cyvasse-board").getBoundingClientRect()
        const army = document.querySelector(".cyvasse-army").getBoundingClientRect()
        return { boardRight: board.right, armyLeft: army.left, pad: getComputedStyle(document.querySelector(".cyvasse-game")).paddingBottom }
      })()
    JS
    assert_operator layout["armyLeft"], :>=, layout["boardRight"], "the army card sits beside the board"
    assert_equal "0px", layout["pad"], "no room kept for a sheet"
  end

  private

  def place_the_army(label)
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_equal "fixed", find(".cyvasse-army").style("position")["position"]
    # The opening scroll runs a frame after the first render.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    opened = in_view
    until opened["board"]["bottom"] <= opened["army"]["top"] + 1 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
      opened = in_view
    end
    assert_both_in_view opened, "when setup opens"
    shot("#{label}-0-open")

    find(".cyvasse-dock .dock-unit", match: :first).click
    assert_selector "svg.cyvasse-board g.hex.is-drop", minimum: 1
    settled = in_view
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
    ready = in_view["ready"]
    assert_button "Ready", disabled: false
    assert_operator ready["bottom"], :<=, in_view["viewport"], "Ready is on the screen"
    shot("#{label}-2-placed")
  end

  def assert_both_in_view(box, moment)
    viewport = box["viewport"]
    board = box["board"]
    army = box["army"]
    assert_operator board["top"], :>=, box["pinned"] - 1, "#{moment}: the board's top is under the navbar"
    assert_operator board["bottom"], :<=, army["top"] + 1, "#{moment}: the sheet covers the board's bottom rows"
    assert_operator army["top"], :>=, 0, "#{moment}: the sheet is off the screen"
    assert_operator army["bottom"], :<=, viewport + 1, "#{moment}: the sheet runs past the screen"
  end

  def in_view
    page.evaluate_script(<<~JS)
      (() => {
        const box = (selector) => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom } }
        const pinned = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--pin-stack-bottom")) || 0
        return { scrollY: window.scrollY, viewport: window.innerHeight, pinned, board: box("svg.cyvasse-board"),
                 army: box(".cyvasse-army"), ready: box(".cyvasse-ready") }
      })()
    JS
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end

  def phone!(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height:, deviceScaleFactor: 2, mobile: true)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
                                    features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
  end

  def shot(name)
    dir = ENV["PHONE_DOCK_SHOTS"]
    return unless dir

    FileUtils.mkdir_p(dir)
    page.save_screenshot(File.join(dir, "phone-dock-#{name}.png"))
  end
end
