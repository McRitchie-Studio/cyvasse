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
