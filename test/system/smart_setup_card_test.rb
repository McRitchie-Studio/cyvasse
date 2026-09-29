require "application_system_test_case"

# [component] [e2e] The "Your army" card at /play and on a match board:
#
# - It opens with "✨ Smart Setup", filled, above the dock, under a centred
#   heading, with no instruction text on show; the fallen card is hidden.
# - Placing a unit turns it into a hollow "✨ Place All" under Ready; a full
#   army makes it "✨ New Setup" and enables Ready.
# - No state change moves Ready, the dock or the card's size, desktop or phone.
# - The fallen card appears, without a reload, when the first unit falls.
#
# SMART_SETUP_SHOTS=<dir> saves each state as smart-setup-*.png there.
class SmartSetupCardTest < ApplicationSystemTestCase
  include MatchPlay

  CARD = ".cyvasse-army".freeze
  SMART = "#{CARD} button.cyvasse-smart".freeze

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  [ [ "desktop", nil ], [ "390", 390 ] ].each do |label, width|
    test "the army card's three states hold still (#{label})" do
      phone!(width) if width
      visit play_path
      assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
      walk_the_three_states(label)
    end
  end

  [ [ "desktop", nil ], [ "390", 390 ] ].each do |label, width|
    test "the match board's army card works the same way (#{label})" do
      arya = make_player("arya")
      match = Match.start_live!(arya, computer: true, rng: Random.new(4))
      sign_in(arya)
      phone!(width) if width
      visit match_path(match)
      assert_selector ".cyvasse-dock .dock-unit", count: 19
      # The live clock shows on its first tick; measure once it has.
      assert_selector "[data-cyvasse-match-target=clockLabel]", text: "Set up your army"
      walk_the_three_states("match-#{label}")
      find_button("Ready").click
      assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10
    end
  end

  test "the fallen card appears, without a reload, when the first unit falls" do
    home = make_player("arya")
    away = make_player("brienne")
    match = started_match(home, away)
    turns = GAME.fetch("turns")
    first_capture = turns.index { |turn| turn.fetch("dead").positive? }
    players = { Match::HOME => home, Match::AWAY => away }
    turns.first(first_capture).each { |turn| match.play!(players.fetch(turn.fetch("mover")), steps_for(turn)) }
    capture = turns.fetch(first_capture)
    mover = players.fetch(capture.fetch("mover"))
    watcher = mover == home ? away : home

    sign_in(watcher)
    visit match_path(match)
    assert_selector "[data-controller=cyvasse-match][data-phase=play][data-your-turn=false]"
    assert_selector "[data-cyvasse-match-target=fallen]", visible: :hidden
    page.execute_script("document.querySelector('[data-controller=cyvasse-match]').dataset.cyvasseMatchPollMsValue = '300'")

    match.play!(mover, steps_for(capture))
    assert_selector "[data-cyvasse-match-target=fallen]", visible: :visible, wait: 10
    assert_selector "[data-cyvasse-match-target=fallen] h2", text: /your fallen/i
    assert_selector ".cyvasse-graveyard img", count: 1
    shot("fallen")
    phone!(390)
    shot("fallen-390")
  end

  private

  def walk_the_three_states(label)
    # 0 placed: Smart Setup leads, filled, above the dock; the heading is
    # centred and the instructions are for screen readers only.
    assert_equal "smart", mode
    assert_button "✨ Smart Setup"
    assert_equal "center", find("#{CARD} h2").style("text-align")["text-align"]
    assert_no_selector "#{CARD} :not(.sr-only)", text: "Pick a unit", exact_text: false
    assert_selector "#{CARD} .sr-only", text: "Pick a unit, then a lit hex", visible: :all
    assert_button "Ready", disabled: true
    start = boxes
    assert_operator start["smart"]["bottom"], :<=, start["dock"]["top"], "Smart Setup sits above the dock"
    assert filled?, "Smart Setup is filled while nothing is placed"
    assert_selector "[data-cyvasse-game-target=fallen], [data-cyvasse-match-target=fallen]", visible: :hidden
    shot("0-#{label}")

    # Some placed: Place All, hollow, under Ready.
    find(".cyvasse-dock .dock-unit", match: :first).click
    find("svg.cyvasse-board g.hex[data-hex='56']").click
    assert_selector "svg.cyvasse-board g.hex[data-hex='56'].has-unit"
    assert_equal "fill", mode
    assert_button "✨ Place All"
    assert_button "Ready", disabled: true
    some = boxes
    assert_operator some["smart"]["top"], :>=, some["ready"]["bottom"], "Place All sits under Ready"
    assert_not filled?, "Place All has no fill"
    assert_still start, some, %w[ready dock card]
    shot("1-#{label}")

    # Place All keeps the placed unit and fills the rest: New Setup.
    placed = find("svg.cyvasse-board g.hex[data-hex='56']")["data-unit-id"]
    find(SMART).click
    assert_equal "new", mode
    assert_button "✨ New Setup"
    assert_button "Ready", disabled: false
    assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='1']", count: 19
    assert_equal placed, find("svg.cyvasse-board g.hex[data-hex='56']")["data-unit-id"], "Place All kept the placed unit"
    all_placed = boxes
    assert_still some, all_placed, %w[ready dock card smart]
    shot("2-#{label}")

    # New Setup replaces the army, and nothing moves.
    find(SMART).click
    assert_equal "new", mode
    assert_still all_placed, boxes, %w[ready dock card smart]
  end

  def mode = find(CARD)["data-army-mode"]

  def filled?
    sleep 0.4 # the button eases between its looks
    page.evaluate_script("getComputedStyle(document.querySelector(#{SMART.to_json})).backgroundColor") !~ /rgba\(0, 0, 0, 0\)|transparent/
  end

  # Each box relative to the card's top-left corner, and the card's relative
  # to the game section (scrolling, and the engine navbar collapsing as the
  # page scrolls, shift the whole page).
  def boxes
    sleep 0.1
    page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector(#{CARD.to_json})
        const origin = card.getBoundingClientRect()
        const box = (el) => { const r = el.getBoundingClientRect(); return { top: r.top - origin.top, bottom: r.bottom - origin.top, left: r.left - origin.left, width: r.width, height: r.height } }
        return {
          card: { top: origin.top - document.querySelector(".cyvasse-game").getBoundingClientRect().top, bottom: origin.height, left: 0, width: origin.width, height: origin.height },
          dock: box(card.querySelector(".cyvasse-dock")),
          ready: box(card.querySelector(".cyvasse-ready")),
          smart: box(card.querySelector(".cyvasse-smart"))
        }
      })()
    JS
  end

  def assert_still(before, after, keys)
    keys.each do |key|
      %w[top left width height].each do |edge|
        assert_in_delta before[key][edge], after[key][edge], 0.5, "#{key} #{edge} moved"
      end
    end
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end

  def phone!(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 844, deviceScaleFactor: 2, mobile: true)
  end

  def shot(name)
    dir = ENV["SMART_SETUP_SHOTS"]
    return unless dir

    FileUtils.mkdir_p(dir)
    find(CARD).scroll_to(:center) if has_selector?(CARD, wait: 0)
    sleep 0.3
    page.save_screenshot(File.join(dir, "smart-setup-#{name}.png"))
  end
end
