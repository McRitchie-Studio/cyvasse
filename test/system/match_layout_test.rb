require "application_system_test_case"

# [e2e] The match page's layout: the board on the left two thirds from the
# top, a sidebar on the right of the versus card over the panel, the clock bar
# across the panel's whole width; a phone stacks versus, board, then panel.
class MatchLayoutSystemTest < ApplicationSystemTestCase
  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @match = Match.start_live!(@arya, computer: true, rng: Random.new(4))
    visit link_path(token: Studio::Link.create_magic_link(email: @arya.email).token)
    assert_text "Signed in as arya"
  end

  def box(css)
    page.evaluate_script(<<~JS)
      (() => { const r = document.querySelector(#{css.to_json}).getBoundingClientRect()
               return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } })()
    JS
      .transform_keys(&:to_sym)
  end

  # docked: a phone's setup, whose army sheet carries the clock, so the timer
  # card's own is not shown as a second one (task cyvasse-play-layout-fit).
  def assert_panel_holds_the_noise(docked: false)
    within("aside.match-panel") do
      if docked
        assert_selector ".cyvasse-army .cyvasse-army-clock", text: /\A\d+s\z/
        assert_no_selector "[data-cyvasse-match-target=clock]", visible: :visible
      else
        assert_selector "[data-cyvasse-match-target=clock]", visible: true
        assert_selector "[data-cyvasse-match-target=clockLabel]", text: "Set up your army"
      end
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

  test "[e2e] desktop: board left from the top, versus card then panel in the sidebar, a full-width clock" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 900, deviceScaleFactor: 1, mobile: false)
    begin
      visit match_path(@match)
      assert_panel_holds_the_noise
      versus, board, panel = [ ".match-versus-card", ".cyvasse-board-wrap", "aside.match-panel" ].map { box(_1) }
      # Task cyvasse-sidebar-reorder lifted the board: the wrap (banner row
      # and all) now starts above the versus card, and the board itself sits
      # near the card's top rather than a banner row and a hint row below it.
      assert_operator board[:top], :<=, versus[:top], "the board's wrap starts level with or above the versus card"
      assert_in_delta versus[:top], box("svg.cyvasse-board")[:top], 32, "the board's top sits near the versus card's"
      assert_operator versus[:bottom], :<=, panel[:top], "the versus card heads the sidebar"
      assert_operator board[:right], :<=, versus[:left], "the versus card sits right of the board"
      assert_in_delta versus[:left], panel[:left], 1
      assert_in_delta versus[:width], panel[:width], 1, "the versus card is as wide as the panel"
      assert_in_delta 2.0, board[:width] / panel[:width], 0.35, "about two thirds to one third"
      assert_clock_spans_the_panel
      page.save_screenshot(Rails.root.join("tmp/screenshots/versus-card-desktop.png")) if ENV["SCREENSHOTS"]
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end

  test "[e2e] phone: versus, board, then the panel, with no sideways scroll" do
    # The phone viewport outlives the test in a shared browser: always undo it.
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    begin
      visit match_path(@match)
      assert_panel_holds_the_noise(docked: true)
      versus, board, panel = [ ".match-versus-card", ".cyvasse-board-wrap", "aside.match-panel" ].map { box(_1) }
      assert_operator versus[:bottom], :<=, board[:top], "the versus card sits above the board"
      assert_operator board[:bottom], :<=, panel[:top], "the panel sits below the board"
      assert_operator versus[:right], :<=, 390
      scroll, client = page_widths
      assert_operator scroll, :<=, client, "no sideways scroll at 390px"
      page.save_screenshot(Rails.root.join("tmp/screenshots/versus-card-phone.png")) if ENV["SCREENSHOTS"]
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end
end
