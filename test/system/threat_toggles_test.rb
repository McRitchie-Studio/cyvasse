require "application_system_test_case"

# [e2e] The Ranged and Melee threat switches, on /play and on a match board:
# each hides only its own units' reach, perimeter and danger, a hex either
# group reaches shows while that group is on, and each choice is remembered.
#
# Staged: their catapult (ranged) on 46, their king and a rabble (melee) on 1
# and 10, a rabble of mine on 66 that only the catapult can take. From
# cyvasse/threats: 5 is reached only by melee, 56 only by ranged, 26 by both.
class ThreatTogglesTest < ApplicationSystemTestCase
  include MatchPlay

  LAYOUT = { "0-15" => 46, "0-17" => 1, "0-1" => 10, "1-17" => 91, "1-1" => 66 }.freeze

  teardown do
    page.execute_script("try { localStorage.clear() } catch {}")
  end

  test "on /play each switch hides only its own threats" do
    start_game
    assert_selector ".cyvasse-board-bar .cyvasse-threat-toggles", visible: true

    exercise("cyvasse-game") { start_game }
  end

  test "on a match board each switch hides only its own threats" do
    home = make_player("arya")
    away = make_player("brienne")
    match = started_match(home, away)
    visit link_path(token: Studio::Link.create_magic_link(email: home.email).token)
    assert_text "Signed in as Arya"
    visit match_path(match)
    assert_selector "[data-controller=cyvasse-match][data-phase=play][data-your-turn=true]"
    assert_selector "aside.match-panel .cyvasse-threat-toggles", visible: true

    exercise("cyvasse-match") do
      visit match_path(match)
      assert_selector "[data-controller=cyvasse-match][data-phase=play]"
    end
  end

  private

  def start_game
    visit play_path
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15
  end

  def exercise(board)
    stage(board)
    assert_threats(ranged: true, melee: true)

    uncheck "Ranged threats"
    assert_threats(ranged: false, melee: true)

    check "Ranged threats"
    uncheck "Melee threats"
    assert_threats(ranged: true, melee: false)

    uncheck "Ranged threats"
    assert_threats(ranged: false, melee: false)

    # Remembered apart: Ranged back on, Melee still off after a reload.
    check "Ranged threats"
    yield
    stage(board)
    assert_checked_field "Ranged threats"
    assert_no_checked_field "Melee threats"
    assert_threats(ranged: true, melee: false)
  end

  def assert_threats(ranged:, melee:)
    threatened = ->(hex) { page.has_selector?("svg.cyvasse-board g.hex.is-threatened[data-hex='#{hex}']", wait: 0) }
    assert_equal({ melee_only: melee, ranged_only: ranged, both: ranged || melee },
                 { melee_only: threatened.(5), ranged_only: threatened.(56), both: threatened.(26) })
    danger = page.evaluate_script("[...document.querySelectorAll('svg.cyvasse-board g.hex.is-danger')].map((g) => g.dataset.hex)")
    assert_equal(ranged ? [ "66" ] : [], danger, "only the catapult can take the rabble")
    count = ->(kind) { page.evaluate_script("document.querySelectorAll('svg.cyvasse-board line.hex-edge[data-kind=#{kind}]').length") }
    assert_equal ranged || melee, count.("perimeter").positive?, "one solid outline while either switch is on"
    assert_equal 0, count.("perimeter-ranged"), "no dashed outline in the default style"
  end

  def stage(board)
    page.execute_script(<<~JS, board, LAYOUT)
      const [identifier, spots] = arguments
      const ctrl = Stimulus.getControllerForElementAndIdentifier(document.querySelector(`[data-controller=${identifier}]`), identifier)
      for (const unit of ctrl.game.units) { unit.status = "dead"; unit.hex = null }
      for (const [id, hex] of Object.entries(spots)) {
        const unit = ctrl.game.unit(id)
        unit.status = "alive"
        unit.hex = hex
      }
      ctrl.game.offense = 1
      ctrl.clearSelection()
      ctrl.render()
    JS
  end
end
