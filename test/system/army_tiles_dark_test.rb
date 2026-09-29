require "application_system_test_case"

# [e2e] The "Your army" dock tiles stay see-through in both themes, and in the
# dark theme each skin's art gets a soft light glow behind it (a radial
# backdrop on the tile, and a light rim on the art) so the pieces read
# against the dark card. The light theme keeps the plain tile and bare art.
#
# ARMY_POLISH_SHOTS=<dir> saves the dark card as army-polish-<skin>-<width>.png.
class ArmyTilesDarkTest < ApplicationSystemTestCase
  CARD = ".cyvasse-army".freeze
  TILE = ".cyvasse-dock .dock-unit".freeze

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  %w[pencil vector].each do |skin|
    [ [ "desktop", nil ], [ "390", 390 ] ].each do |label, width|
      test "#{skin} tiles read in the dark theme, see-through, at #{label}" do
        phone!(width) if width
        visit play_path(skin: skin)
        assert_selector "[data-controller=cyvasse-game][data-skin=#{skin}]"
        assert_selector TILE, count: 19

        theme!(dark: true)
        shot("#{skin}-#{label}")
        look = tile_look
        assert_match(/radial-gradient/, look["backdrop"], "a soft glow sits behind the art in the dark theme")
        assert_match(/drop-shadow/, look["filter"], "the art carries a light rim in the dark theme")
        assert_equal "rgba(0, 0, 0, 0)", look["background"], "the tile itself stays see-through: no opaque fill"

        theme!(dark: false)
        look = tile_look
        assert_equal "none", look["backdrop"], "no glow in the light theme"
        assert_equal "none", look["filter"], "the art is bare in the light theme"
        assert_equal "rgba(0, 0, 0, 0)", look["background"]
      ensure
        theme!(dark: true)
      end
    end
  end

  # A phone has no hover, and a tap leaves :hover stuck on what it touched;
  # the army card's hover tints live only under @media (hover: hover).
  test "the army card's hover tints apply only where there is a hover" do
    visit play_path
    assert_selector TILE, count: 19
    loose = page.evaluate_script(<<~JS)
      (() => {
        const loose = []
        const walk = (rules, hover) => {
          for (const rule of rules) {
            if (rule.media) walk(rule.cssRules, hover || /\\(hover:\\s*hover\\)/.test(rule.media.mediaText))
            else if (rule.cssRules) walk(rule.cssRules, hover)
            else if (/(dock-unit|cyvasse-smart|cyvasse-ready)[^,]*:hover/.test(rule.selectorText || "") && !hover) loose.push(rule.selectorText)
          }
        }
        for (const sheet of document.styleSheets) {
          try { walk(sheet.cssRules, false) } catch (e) { /* a cross-origin sheet */ }
        }
        return loose
      })()
    JS
    assert_empty loose, "hover rules outside @media (hover: hover)"
    assert_operator page.evaluate_script("[...document.styleSheets].flatMap((s) => { try { return [...s.cssRules] } catch (e) { return [] } }).filter((r) => r.media && /hover: hover/.test(r.media.mediaText) && /dock-unit:hover/.test(r.cssText)).length"), :>=, 1, "the tile's hover tint is still there for a mouse"
  end

  private

  def tile_look
    page.evaluate_script(<<~JS)
      (() => {
        const tile = document.querySelector(#{TILE.to_json})
        const style = getComputedStyle(tile)
        return {
          backdrop: style.backgroundImage,
          background: style.backgroundColor,
          filter: getComputedStyle(tile.querySelector("img")).filter
        }
      })()
    JS
  end

  def theme!(dark:)
    page.execute_script("document.documentElement.classList.#{dark ? 'add' : 'remove'}('dark')")
  end

  def phone!(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 844, deviceScaleFactor: 2, mobile: true)
  end

  def shot(name)
    dir = ENV["ARMY_POLISH_SHOTS"]
    return unless dir

    FileUtils.mkdir_p(dir)
    page.execute_script("document.querySelector(#{CARD.to_json}).scrollIntoView({ block: 'center' })")
    sleep 0.4
    page.save_screenshot(File.join(dir, "army-polish-#{name}.png"))
  end
end
