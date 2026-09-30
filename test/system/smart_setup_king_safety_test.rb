require "application_system_test_case"

# [e2e] Task cyvasse-smart-setup-king-safety, in a real browser at /play.
#
# Production UX audit #2 (September 30, 2026) found about one Smart Setup in
# six lost its king to the computer's first move, before the player moved: an
# enemy light horse took the shooter standing in front of the king (shooters
# defend at 1) and then the king. And after Smart Setup the Openings picker
# still said "Iron Corner", whatever stood on the board.
#
# - Over a seeded batch of Smart Setups and New Setups, the page's own engine
#   plays every first turn of every computer army against the army on the
#   board, and none takes the king; then a real game starts, and when the
#   computer moves first its move leaves the king standing.
# - The picker names the opening on the board after each Smart Setup and New
#   Setup, with that opening's idea, and says "Custom" once a unit is moved.
class SmartSetupKingSafetyTest < ApplicationSystemTestCase
  BOARD = "[data-controller=cyvasse-game]".freeze
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('#{BOARD}'), 'cyvasse-game')".freeze
  PICKER = "[data-controller=cyvasse-openings]".freeze
  SEEDS = [ 3, 17, 42, 101, 977, 2026 ].freeze
  NEW_SETUPS = 8

  test "no Smart Setup or New Setup leaves the king to any computer's first turn, over a seeded batch" do
    SEEDS.each do |seed|
      with_seeded_random(seed) do
        visit play_path
        assert_controllers_connected("cyvasse-game", "cyvasse-openings")
        smart_setup!
        assert_no_first_turn_takes_the_king("seed #{seed}")
        assert_picker_names_the_board("seed #{seed}")
        play_until_the_computer_has_moved("seed #{seed}")
      end
    end
  end

  test "New Setup deals opening after opening, each safe and each named by the picker" do
    with_seeded_random(7) do
      visit play_path
      assert_controllers_connected("cyvasse-game", "cyvasse-openings")
      smart_setup!
      seen = []
      NEW_SETUPS.times do |i|
        seen << assert_picker_names_the_board("new setup #{i}")
        assert_no_first_turn_takes_the_king("new setup #{i}")
        find("button.cyvasse-smart", text: "New Setup").click
        assert_no_selector "#{PICKER} select option:checked[value='#{seen.last}']"
      end
      assert_equal seen.uniq, seen, "New Setup never repeats one of the last ten"
      screenshot("new-setup-named")
    end
  end

  test "the picker says Custom once a unit of the placed opening is moved" do
    with_seeded_random(11) do
      visit play_path
      assert_controllers_connected("cyvasse-game", "cyvasse-openings")
      smart_setup!
      assert_picker_names_the_board("smart setup")

      from, to = page.evaluate_script(<<~JS)
        (() => {
          const game = #{CONTROLLER}.game
          const unit = game.teamUnits(1).find((u) => u.type.codename === "rabble")
          const free = [...Array(40)].map((_, i) => 52 + i).find((hex) => !game.pieceAt(hex))
          return [unit.hex, free]
        })()
      JS
      find("svg.cyvasse-board g.hex[data-hex='#{from}']").click
      find("svg.cyvasse-board g.hex[data-hex='#{to}']").click
      assert_selector "svg.cyvasse-board g.hex[data-hex='#{to}'][data-unit='rabble']"

      assert_selector "#{PICKER} select option:checked", text: "Custom"
      assert_selector "#{PICKER} [data-cyvasse-openings-target=idea]", text: "Your own lineup"
      screenshot("custom")
      within(PICKER) { click_on "Load opening" }
      assert_selector "#{PICKER} [role=status]", text: "Pick an opening to load."
    end
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/smart-setup-king-safety-#{name}.png").to_s)
  end

  # The page's own engine (the importmap's cyvasse/*) plays every first turn
  # of every computer lineup against the army on the board, both jumps of a
  # cavalry unit included, and answers the ones that take the king.
  def assert_no_first_turn_takes_the_king(label)
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      Promise.all([import("cyvasse/game"), import("cyvasse/setups")]).then(([{ Game, COMPUTER, PLAYER }, { COMPUTER_OPPONENTS }]) => {
        const lineup = #{CONTROLLER}.game.playerLineup()
        const falls = []
        for (const { name, lineups } of COMPUTER_OPPONENTS) {
          for (const computer of lineups) {
            const game = new Game({ computer: { name, lineup: computer } })
            game.loadLineup(lineup)
            game.start()
            game.offense = COMPUTER
            const king = game.teamUnits(PLAYER).find((u) => u.type.codename === "king")
            const tryAll = (from, depth) => {
              const { moves, attacks } = game.actionsFrom(from)
              for (const to of [...moves, ...attacks]) {
                const before = game.snapshot()
                const result = game.act(from, to)
                if (king.status === "dead") falls.push(`${name}: ${from}->${to}`)
                else if (result.secondJump && depth === 1) tryAll(game.activeHex, 2)
                game.restoreSnapshot(before)
              }
            }
            for (const from of game.selectableHexes()) tryAll(from, 1)
          }
        }
        done({ lineup, falls })
      }).catch((error) => done({ error: String(error) }))
    JS
    assert_nil result["error"], "#{label}: #{result["error"]}"
    assert_empty result["falls"], "#{label}: #{result["lineup"]} loses its king"
  end

  # The picker's selected option is the opening whose lineup stands on the
  # board, never "Custom" and never left on Iron Corner by default; its idea
  # is that opening's. Answers the slug.
  def assert_picker_names_the_board(label)
    named = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("cyvasse/openings").then(({ OPENINGS, openingLineup }) => {
        const board = #{CONTROLLER}.game.playerLineup()
        const placed = OPENINGS.find((o) => openingLineup(o) === board)
        const select = document.querySelector("#{PICKER} select")
        done({ placed: placed?.slug ?? null, idea: placed?.idea ?? null, selected: select.value,
               shown: document.querySelector("#{PICKER} [data-cyvasse-openings-target=idea]").textContent })
      })
    JS
    refute_nil named["placed"], "#{label}: Smart Setup placed an opening"
    assert_equal named["placed"], named["selected"], "#{label}: the picker names the opening on the board"
    assert_equal named["idea"], named["shown"], "#{label}: and shows its idea"
    named["placed"]
  end

  # Ready, then no delays; if the computer has the first move, wait for it
  # and check the king still stands.
  def play_until_the_computer_has_moved(label)
    click_on "Ready"
    assert_selector "#{BOARD}[data-phase=play]"
    page.execute_script("document.querySelector('#{BOARD}').dataset.cyvasseGamePaceValue = '0'")
    return unless find(BOARD)["data-offense"] == "0" && find(BOARD)["data-turn"] == "1"

    assert_selector "#{BOARD}[data-turn='2'], #{BOARD}[data-phase=over]", wait: 30
    refute_equal "over", find(BOARD)["data-phase"], "#{label}: the computer's first move ended the game"
    assert_selector "svg.cyvasse-board g.hex[data-unit-id='1-17'][data-unit=king]"
  end
end
