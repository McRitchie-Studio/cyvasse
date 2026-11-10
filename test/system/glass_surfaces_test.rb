# frozen_string_literal: true

require "application_system_test_case"

# [e2e] Cyvasse on the engine's glass in a real browser (task
# cyvasse-adopts-glass-style), at 1280px and 390px, light and dark. The server
# tier (test/components/glass_surface_adoption_test.rb) proves the markup. Only
# a browser proves the paint: a card is translucent, the navbar and the sidebar
# panel blur, the panel wears Cyvasse's parchment ink and not the hub's violet,
# and on the board page the game keeps its look: no ambient glow behind the
# board, and the game-over modal's buttons are not lit.
class GlassSurfacesSystemTest < ApplicationSystemTestCase
  include LiveResults

  # The panel's ink: #2B2418 in light, #F7F4EC in dark.
  INK = { "light" => "rgb(43, 36, 24)", "dark" => "rgb(247, 244, 236)" }.freeze

  setup do
    @arya = player("arya")
    visit_magic_link(Studio::Link.create_magic_link(email: @arya.email).token)
  end

  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  # Headless Chrome will not shrink its window below about 500px, so the
  # viewport is set through the DevTools protocol, as navbar_links_test does.
  def resize_to(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: height, deviceScaleFactor: 1, mobile: width < 640)
  end

  def visit_in(theme, path)
    visit path
    page.execute_script("localStorage.setItem('theme', arguments[0])", theme)
    visit path
    assert_selector "html[data-surface-style='glass']#{theme == 'dark' ? '.dark' : ':not(.dark)'}", visible: :all
  end

  def style_of(selector, property, pseudo = nil)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json}), #{pseudo.to_json}).#{property}")
  end

  # The alpha of a computed colour: rgba(...) or color(srgb ... / a), else 1.
  def alpha(color)
    color[%r{/\s*([\d.]+)\s*\)}, 1]&.to_f || color[/rgba\([^)]*,\s*([\d.]+)\)/, 1]&.to_f || 1.0
  end

  [ [ 1280, 900 ], [ 390, 844 ] ].each do |width, height|
    %w[light dark].each do |theme|
      test "#{width}px #{theme}: translucent cards, a blurred navbar and the parchment glass sidebar" do
        resize_to(width, height)
        visit_in(theme, "/rules")

        assert_selector ".card", minimum: 1
        assert_operator alpha(style_of(".card", "backgroundColor")), :<, 1, "a card must be translucent"
        assert_includes style_of(".nav-shell", "backdropFilter"), "blur"
        refute_equal "none", style_of("body", "backgroundImage", "::before"), "a reading page lays the ambient glow"

        find("[data-link-sidebar-trigger]", match: :first, visible: true).click
        shell = "[data-sidebar-glass-shell]"
        assert_selector shell, visible: true
        ink = page.evaluate_script(<<~JS)
          (() => { const el = [...document.querySelectorAll(#{shell.to_json})].find((n) => n.getClientRects().length);
                   const s = getComputedStyle(el); return [s.color, s.backdropFilter]; })()
        JS
        assert_equal INK[theme], ink[0], "the sidebar must wear Cyvasse's parchment ink"
        assert_includes ink[1], "blur"
        assert_operator page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth"), :<=, 0
      end

      test "#{width}px #{theme}: the board page keeps a plain ground and unlit game-over buttons" do
        resize_to(width, height)
        visit_in(theme, "/play")
        assert_controllers_connected("cyvasse-game")

        assert_equal "none", style_of("body", "backgroundImage", "::before"), "no ambient glow behind the board"
        assert_operator alpha(style_of(".cyvasse-panel .card:not(.cyvasse-army)", "backgroundColor")), :<, 1,
                        "the panels beside the board are glass"
        if width < 1024
          assert_equal 1.0, alpha(style_of(".cyvasse-setup-controls .cyvasse-army", "backgroundColor")),
                       "the docked army sheet over the board stays solid"
        end

        page.execute_script("Alpine.store('modals').open('game-over', { result: 'You won!', points: 0 })")
        button = "[data-test=game-over-modal] .btn-primary"
        assert_selector button, visible: true
        assert_equal "none", style_of(button, "backgroundImage"), "the game-over buttons are not lit"
        assert_equal "none", style_of(button, "content", "::after")
        assert_equal 1.0, alpha(style_of(button, "backgroundColor"))
        assert_operator page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth"), :<=, 0
      end
    end
  end
end
