require "application_system_test_case"

# [component] [e2e] The "Your army" card at /play and on a match board:
#
# - It opens with "✨ Smart Setup", filled, beside Ready, both above the dock,
#   under a centred heading, with no instruction text on show; the fallen
#   card is hidden. (Task cyvasse-sidebar-reorder moved Ready from under the
#   dock to beside Smart Setup, above it; Smart Setup no longer moves from a
#   lead row to a tail row as the army is placed.)
# - Placing a unit turns it into a hollow "✨ Place All", still beside Ready;
#   a full army makes it "✨ New Setup" and enables Ready.
# - No state change moves Ready, Smart Setup, the dock, the card's size or
#   the status above them, desktop or phone.
# - On a phone (390px) the card is docked, a sheet fixed to the bottom of the
#   screen (task cyvasse-phone-setup-dock): the heading sits left over the
#   count, and Smart Setup keeps one place, beside Ready, in every state.
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
      walk_the_three_states(label, docked: !width.nil?)
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
      # The live clock shows on its first tick; measure once it has. A docked
      # phone sheet carries it, and the timer card's own is not shown there
      # (task cyvasse-play-layout-fit).
      if width
        assert_selector ".cyvasse-army .cyvasse-army-clock", text: /\A\d+s\z/
      else
        assert_selector "[data-cyvasse-match-target=clockLabel]", text: "Set up your army"
      end
      walk_the_three_states("match-#{label}", docked: !width.nil?)
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

  def walk_the_three_states(label, docked: false)
    # 0 placed: Smart Setup leads, filled, above the dock (docked: beside
    # Ready, under it); the heading is centred (docked: left, over the
    # count) and the instructions are for screen readers only.
    assert_equal "smart", mode
    assert_button "✨ Smart Setup"
    assert_equal docked ? "left" : "center", find("#{CARD} h2").style("text-align")["text-align"]
    assert_equal docked ? "fixed" : "static", find(CARD).style("position")["position"]
    assert_no_selector "#{CARD} :not(.sr-only)", text: "Pick a unit", exact_text: false
    assert_selector "#{CARD} .sr-only", text: "Pick a unit, then a lit hex", visible: :all
    assert_button "Ready", disabled: true
    start = boxes
    assert_beside_ready start, docked
    if docked
      assert_in_delta page.evaluate_script("window.innerHeight"), start["card"]["top"] + start["card"]["height"], 1, "the sheet sits on the screen's bottom edge"
    end
    assert filled?, "Smart Setup is filled while nothing is placed"
    assert_selector "[data-cyvasse-game-target=fallen], [data-cyvasse-match-target=fallen]", visible: :hidden
    shot("0-#{label}")

    # Some placed: Place All, hollow, under Ready.
    find(".cyvasse-dock .dock-unit", match: :first).click
    find("svg.cyvasse-board g.hex[data-hex='56']").click
    assert_selector "svg.cyvasse-board g.hex[data-hex='56'].has-unit"
    assert_equal "fill", mode
    assert_button "✨ Place All"
    assert_selector "#{SMART} span[aria-hidden=true]", text: "✨", count: 1
    # The count shows only in the phone sheet; the sidebar card says it in
    # its status (task cyvasse-sidebar-reorder).
    assert_selector "#{CARD} .cyvasse-army-count[aria-hidden=true]", text: "1 of 19 placed", visible: docked ? :visible : :all
    assert_selector "#{CARD} .cyvasse-army-count", visible: :visible, count: 0 unless docked
    assert_selector "[role=status][aria-live=polite]", text: "Place your army: 1 of 19 placed."
    assert_selector "[aria-live]", text: /of 19 placed/, count: 1
    assert_button "Ready", disabled: true
    some = boxes
    assert_beside_ready some, docked
    assert_not filled?, "Place All has no fill"
    assert_still start, some, %w[ready smart dock card status]
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
    assert_still some, all_placed, %w[ready dock card smart status]
    shot("2-#{label}")

    # New Setup replaces the army, and nothing moves.
    find(SMART).click
    assert_equal "new", mode
    assert_still all_placed, boxes, %w[ready dock card smart status]
  end

  def mode = find(CARD)["data-army-mode"]

  # Smart Setup and Ready share a row: above the dock in the sidebar, under
  # it in the phone sheet (in thumb reach).
  def assert_beside_ready(box, docked)
    assert_in_delta box["ready"]["top"], box["smart"]["top"], 0.5, "Smart Setup shares Ready's row"
    assert_operator box["smart"]["left"] + box["smart"]["width"], :<=, box["ready"]["left"], "Smart Setup sits left of Ready"
    if docked
      assert_operator box["smart"]["top"], :>=, box["dock"]["bottom"], "the buttons sit under the dock"
    else
      assert_operator box["ready"]["bottom"], :<=, box["dock"]["top"], "the buttons sit above the dock"
    end
  end

  def filled?
    sleep 0.4 # the button eases between its looks
    page.evaluate_script("getComputedStyle(document.querySelector(#{SMART.to_json})).backgroundColor") !~ /rgba\(0, 0, 0, 0\)|transparent/
  end

  # Each box relative to the card's top-left corner; the card's top relative
  # to whatever sits above it in the sidebar (scrolling, the engine navbar
  # collapsing, and a live match's notices arriving on their own all shift
  # the page; a docked card, fixed to the screen, relative to the screen's
  # top); and the status line's height, which reserves room for its longest
  # setup text. On a match that is the army card's copy of the status line
  # (the line itself is read, not shown, while the card is up).
  def boxes
    sleep 0.1
    page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector(#{CARD.to_json})
        const origin = card.getBoundingClientRect()
        const wrap = card.parentElement
        const fixed = getComputedStyle(card).position === "fixed"
        const above = fixed ? 0 : wrap.previousElementSibling ? wrap.previousElementSibling.getBoundingClientRect().bottom : wrap.parentElement.getBoundingClientRect().top
        const copy = card.querySelector(".cyvasse-army-status")
        const status = (copy && copy.offsetParent ? copy : document.querySelector("[data-cyvasse-match-target=status], [data-cyvasse-game-target=status]")).getBoundingClientRect()
        const box = (el) => { const r = el.getBoundingClientRect(); return { top: r.top - origin.top, bottom: r.bottom - origin.top, left: r.left - origin.left, width: r.width, height: r.height } }
        return {
          card: { top: origin.top - above, bottom: origin.height, left: 0, width: origin.width, height: origin.height },
          status: { top: 0, left: 0, width: 0, height: status.height },
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
    assert_text "Signed in as #{user.player_name}"
  end

  def phone!(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 844, deviceScaleFactor: 2, mobile: true)
  end

  def shot(name)
    dir = ENV["SMART_SETUP_SHOTS"]
    return unless dir

    FileUtils.mkdir_p(dir)
    target = has_selector?(CARD, wait: 0) ? CARD : ".cyvasse-graveyard"
    page.execute_script("document.querySelector(#{target.to_json}).scrollIntoView({ block: 'center' })")
    sleep 0.5
    page.save_screenshot(File.join(dir, "smart-setup-#{name}.png"))
  end
end
