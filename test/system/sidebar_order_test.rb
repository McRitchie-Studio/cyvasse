require "application_system_test_case"

# [e2e] The match sidebar's order (task cyvasse-sidebar-reorder), as laid out
# at 1440px and 390px, in setup and in play:
#
# - setup: the timer card, the army card (its status copy, Smart Setup
#   beside Ready, then the units), then the links and the forfeit, last;
# - play: the timer card with the threat switches under the clock, the unit
#   card, the status line, then the links and the forfeit, last;
# - once the army is placed, "Your army is in place..." is announced by the
#   status line but shown nowhere in the sidebar;
# - on desktop the board's top sits near the versus card's; on a phone the
#   army card still docks as a sheet; no width scrolls sideways.
#
# SIDEBAR_SHOTS=<dir> saves each as sidebar-reorder-*.png there.
class SidebarOrderTest < ApplicationSystemTestCase
  include MatchPlay

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  [ [ "1440", 1440, false ], [ "390", 390, true ] ].each do |label, width, phone|
    test "setup reads timer, army card led by Ready, then the links (#{label})" do
      arya = make_player("arya")
      match = Match.start_live!(arya, computer: true, rng: Random.new(4))
      sign_in(arya)
      size!(width, phone)
      visit match_path(match)
      assert_controllers_connected "cyvasse-match"
      assert_selector ".cyvasse-dock .dock-unit", count: 19
      assert_selector "[data-cyvasse-match-target=clockLabel]", text: "Set up your army"

      assert_selector ".cyvasse-army-status", text: "Place your army: 0 of 19 placed.", visible: !phone
      assert_equal "1px", find(".match-status-line", visible: :all).style("width")["width"], "the status line is read, not shown"
      assert_equal "Place your army: 0 of 19 placed.", find(".match-status-line", visible: :all)[:textContent].strip

      if phone
        assert_equal "fixed", find(".cyvasse-army").style("position")["position"], "the army card docks as a sheet"
      else
        tops = tops_of(".match-versus-card", ".match-panel-status", ".cyvasse-army", ".cyvasse-army-status",
                       ".cyvasse-ready", ".cyvasse-dock", ".cyvasse-setup-controls > .card:not(.cyvasse-army)", ".match-actions")
        assert_equal tops.values.sort, tops.values, "top to bottom: #{tops.inspect}"
        assert_in_delta tops[".match-versus-card"], top_of("svg.cyvasse-board"), 32, "the board's top sits near the versus card's"
      end
      assert_last_in_sidebar ".match-actions"
      assert_no_sideways_scroll width
      shot("setup-#{label}")

      # A placed army is announced, not shown (Alex, task
      # cyvasse-sidebar-reorder): the enabled Ready says it for the eye.
      smart_setup!
      assert_button "Ready", disabled: false
      line = find(".match-status-line[role=status][aria-live=polite]", visible: :all)
      assert_equal "Your army is in place. Press Ready to lock it in.", line[:textContent].strip, "screen readers still hear it"
      assert_equal "1px", line.style("width")["width"], "the status line is read, not shown"
      # Capybara counts a clipped (sr-only) node as visible, so ask the layout:
      # no rendered box larger than the 1px clip carries the sentence.
      shown = page.evaluate_script(<<~JS)
        [...document.querySelectorAll("aside.match-panel *")]
          .filter((el) => el.checkVisibility() && el.getBoundingClientRect().width > 1 && el.getBoundingClientRect().height > 1)
          .filter((el) => [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.includes("Your army is in place")))
          .map((el) => el.className)
      JS
      assert_empty shown, "the sentence shows nowhere in the sidebar"
      assert_equal "", find(".cyvasse-army-status", visible: :all)[:textContent].strip, "the army card's copy is blank"
    end

    test "play reads timer with the switches, unit card, status, then the links (#{label})" do
      home = make_player("arya")
      match = started_match(home, make_player("brienne"))
      sign_in(home)
      size!(width, phone)
      visit match_path(match)
      assert_selector "[data-controller=cyvasse-match][data-phase=play][data-your-turn=true]"
      find("svg.cyvasse-board g.hex.has-unit[data-team='1']", match: :first).click
      assert_selector "[data-cyvasse-match-target=info]", visible: :visible
      assert_selector ".match-status-line[role=status]", text: /Turn 1: your move\. \w.* selected/

      within(".match-panel-status") { assert_selector ".cyvasse-threat-toggle", count: 2, visible: :visible }
      tops = tops_of(".match-versus-card", ".match-panel-status", ".match-panel-status .cyvasse-threat-toggles",
                     "[data-cyvasse-match-target=info]", ".match-status-line", ".match-actions")
      tops.delete(".match-versus-card") if phone # a phone puts the board between versus and the panel
      assert_equal tops.values.sort, tops.values, "top to bottom: #{tops.inspect}"
      assert_in_delta tops[".match-versus-card"], top_of("svg.cyvasse-board"), 32, "the board's top sits near the versus card's" unless phone
      assert_last_in_sidebar ".match-actions"
      assert_no_sideways_scroll width
      shot("play-#{label}")

      # The banner slot shares the hint's row on desktop, drawn over it; a
      # click on the hint must still reach it and put the unit back.
      find(".cyvasse-hint", visible: :visible).click
      assert_selector "[data-cyvasse-match-target=info]", visible: :hidden
    end
  end

  private

  def tops_of(*selectors) = selectors.to_h { [ _1, top_of(_1) ] }

  def top_of(css)
    page.evaluate_script("document.querySelector(#{css.to_json}).getBoundingClientRect().top + window.scrollY")
  end

  def assert_last_in_sidebar(css)
    last = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("aside.match-panel > *")].filter((el) => getComputedStyle(el).display !== "none").pop().matches(#{css.to_json})
    JS
    assert last, "#{css} closes the sidebar"
  end

  def assert_no_sideways_scroll(width)
    scroll, client = page_widths
    assert_operator scroll, :<=, client, "no sideways scroll at #{width}px"
  end

  def size!(width, phone)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height: phone ? 844 : 1000, deviceScaleFactor: 1, mobile: phone)
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.player_name}"
  end

  def shot(name)
    dir = ENV["SIDEBAR_SHOTS"]
    return unless dir

    FileUtils.mkdir_p(dir)
    page.save_screenshot(File.join(dir, "sidebar-reorder-e2e-#{name}.png"))
  end
end
