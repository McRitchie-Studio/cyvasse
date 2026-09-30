require "application_system_test_case"

# [e2e] A player's name never breaks mid-word (task cyvasse-splash-name-fit).
# Alex's own name split "alex_mcritchi" / "e" on the Play Now splash, because
# the name wrapped anywhere. A username is one word: it stays on one line,
# shrinks to fit its card, and only at the floor is it cut with an ellipsis
# (the whole name in its title). A two-word computer name may wrap, but only
# at its space. Measured at desktop (1440) and phone (390) widths.
class PlayerNameFitTest < ApplicationSystemTestCase
  include MatchPlay

  LONG_NAME = "alexander_mcritchie1".freeze # the longest a username may be: 20
  WIDTHS = { "1440" => [ 1440, 1000 ], "390" => [ 390, 844 ] }.freeze

  # How a name element lays out: the lines its text takes, the lines each of
  # its words takes (2 = broken mid-word), whether it is cut, and its size.
  LAYOUT_JS = <<~JS.freeze
    ((el) => {
      const node = [...el.childNodes].find((n) => n.nodeType === Node.TEXT_NODE)
      const text = node ? node.textContent : ""
      const lines = (start, end) => {
        const range = document.createRange()
        range.setStart(node, start)
        range.setEnd(node, end)
        return new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top))).size
      }
      const words = []
      for (const m of text.matchAll(/\\S+/g)) words.push(lines(m.index, m.index + m[0].length))
      const style = getComputedStyle(el)
      return {
        text, words, lines: node ? lines(0, text.length) : 0,
        cut: el.scrollWidth > el.clientWidth,
        title: el.title,
        height: el.getBoundingClientRect().height,
        lineHeight: parseFloat(style.lineHeight),
        fontSize: parseFloat(style.fontSize),
        wrap: style.overflowWrap, wordBreak: style.wordBreak
      }
    })
  JS

  setup do
    Rails.configuration.x.live_search_time = 20.seconds
    Rails.configuration.x.live_splash_time = 60.seconds # the splash holds while we measure
    @me = User.create!(email: "alexander@example.com", name: "Alexander McRitchie", username: LONG_NAME)
  end

  teardown do
    Rails.configuration.x.live_search_time = nil
    Rails.configuration.x.live_splash_time = nil
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "the splash keeps a 20-character username on one line, and wraps a computer's name only at its space" do
    sign_in(@me)
    click_on "Play Now"
    assert_text "Finding an opponent"
    click_on "Play the computer now"
    assert_text(/match found/i, wait: 5)
    assert_selector "[data-live-seek-target=computerTag]", text: "Computer"

    WIDTHS.each do |label, (width, height)|
      at_width(width, height) do
        you = settled_layout("[data-live-seek-target=you]", LONG_NAME)
        screenshot("splash-name-#{label}")
        assert_one_line you, "the splash at #{label}"

        # A computer's two-word name: at most one break, and only at the space.
        page.execute_script("document.querySelector('[data-live-seek-target=opponent]').textContent = 'Tyrion Lannister'")
        bot = settled_layout("[data-live-seek-target=opponent]", "Tyrion Lannister")
        assert_equal [ 1, 1 ], bot[:words], "at #{label} a word of the computer's name broke: #{bot.inspect}"
        assert_operator bot[:lines], :<=, 2, "at #{label}: #{bot.inspect}"
      end
    end
  end

  test "the match's versus card and the navbar keep a 20-character username on one line" do
    match = Match.start_live!(@me, computer: true, rng: Random.new(7))
    sign_in(@me)
    visit match_path(match)
    assert_selector ".match-versus-card"

    WIDTHS.each do |label, (width, height)|
      at_width(width, height) do
        mine = settled_layout(".match-versus-side[data-side=me] .match-versus-name", LONG_NAME)
        screenshot("versus-name-#{label}")
        assert_one_line mine, "the versus card at #{label}"
        bot = settled_layout(".match-versus-side[data-side=them] .match-versus-name", match.away_user.player_name)
        assert bot[:words].all?(1), "at #{label} a word of the computer's name broke: #{bot.inspect}"
        navbar = page.evaluate_script(<<~JS)
          (() => {
            const el = [...document.querySelectorAll("header[data-pin=nav] *")].find((n) =>
              n.children.length === 0 && n.textContent.trim() === #{LONG_NAME.to_json} && n.getClientRects().length > 0)
            return el ? (#{LAYOUT_JS.strip})(el) : null
          })()
        JS
        assert navbar, "the navbar shows the username at #{label}" if label == "1440"
        assert_equal 1, navbar["lines"], "the navbar name at #{label}: #{navbar.inspect}" if navbar
      end
    end
  end

  private

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.player_name}"
  end

  # Chrome will not size a window below 500px, so a phone is emulated.
  def at_width(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 500)
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  # The name's layout once it shows `text` and its fit has settled (the fit
  # answers a resize a frame later).
  def settled_layout(selector, text)
    assert_selector selector, text: text, exact_text: true
    previous = nil
    page.document.synchronize(5) do
      sleep 0.15
      layout = page.evaluate_script("(#{LAYOUT_JS.strip})(document.querySelector(#{selector.to_json}))").symbolize_keys
      settled = layout == previous
      previous = layout
      raise Capybara::ExpectationNotMet, "still fitting" unless settled

      layout
    end
  end

  def assert_one_line(layout, where)
    assert_equal 1, layout[:lines], "#{where}: the name takes more than one line: #{layout.inspect}"
    assert layout[:words].all?(1), "#{where}: the name broke mid-word: #{layout.inspect}"
    assert_operator layout[:height], :<, layout[:lineHeight] * 1.5, "#{where}: taller than one line: #{layout.inspect}"
    assert_not_equal "anywhere", layout[:wrap], "#{where}: may still break anywhere"
    assert_not_equal "break-all", layout[:wordBreak], "#{where}: may still break anywhere"
    assert(!layout[:cut] || layout[:title] == layout[:text], "#{where}: cut with no full name to read: #{layout.inspect}")
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
