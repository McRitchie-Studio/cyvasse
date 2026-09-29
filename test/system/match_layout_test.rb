require "application_system_test_case"

# [e2e] The match page's layout: the versus row across the top, the board on
# the left two thirds and the panel on the right, the clock bar across the
# panel's whole width; a phone stacks versus, board, then panel.
class MatchLayoutSystemTest < ApplicationSystemTestCase
  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @match = Match.start_live!(@arya, computer: true, rng: Random.new(4))
    visit link_path(token: Studio::Link.create_magic_link(email: @arya.email).token)
    assert_text "Signed in as Arya"
  end

  def box(css)
    page.evaluate_script(<<~JS)
      (() => { const r = document.querySelector(#{css.to_json}).getBoundingClientRect()
               return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } })()
    JS
      .transform_keys(&:to_sym)
  end

  def assert_panel_holds_the_noise
    within("aside.match-panel") do
      assert_selector "[data-cyvasse-match-target=clock]", visible: true
      assert_selector "[data-cyvasse-match-target=clockLabel]", text: "Set up your army"
      assert_link "← My games"
      assert_link "How to play"
      assert_button "Forfeit match"
    end
    assert_no_text "Cancel match"
  end

  # The bar spans the panel card's content box.
  def assert_clock_spans_the_panel
    track = box(".match-panel .live-clock-track")
    card = box(".match-panel-status")
    assert_in_delta card[:width] - 32, track[:width], 2, "the clock bar spans the panel"
  end

  test "[e2e] desktop: versus across the top, board left, panel right with a full-width clock" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 900, deviceScaleFactor: 1, mobile: false)
    begin
      visit match_path(@match)
      assert_panel_holds_the_noise
      versus, board, panel = [ "h1.match-versus", ".cyvasse-board-wrap", "aside.match-panel" ].map { box(_1) }
      assert_operator versus[:bottom], :<=, board[:top]
      assert_operator versus[:bottom], :<=, panel[:top]
      assert_operator board[:right], :<=, panel[:left], "the panel sits right of the board"
      assert_operator versus[:width], :>=, board[:width] + panel[:width], "the versus row spans both"
      assert_in_delta 2.0, board[:width] / panel[:width], 0.35, "about two thirds to one third"
      assert_clock_spans_the_panel
      page.save_screenshot(Rails.root.join("tmp/screenshots/match-layout-desktop.png")) if ENV["SCREENSHOTS"]
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end

  test "[e2e] phone: versus, board, then the panel, with no sideways scroll" do
    # The phone viewport outlives the test in a shared browser: always undo it.
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    begin
      visit match_path(@match)
      assert_panel_holds_the_noise
      versus, board, panel = [ "h1.match-versus", ".cyvasse-board-wrap", "aside.match-panel" ].map { box(_1) }
      assert_operator versus[:bottom], :<=, board[:top]
      assert_operator board[:bottom], :<=, panel[:top]
      assert_clock_spans_the_panel
      scroll, client = page_widths
      assert_operator scroll, :<=, client, "no sideways scroll at 390px"
      page.save_screenshot(Rails.root.join("tmp/screenshots/match-layout-phone.png")) if ENV["SCREENSHOTS"]
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end
end
