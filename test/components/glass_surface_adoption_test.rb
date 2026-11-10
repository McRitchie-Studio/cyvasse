# frozen_string_literal: true

require "test_helper"

# [component] Cyvasse on the engine's glass (task cyvasse-adopts-glass-style).
#
# The engine owns the glass: engine.css, THE GLASS SURFACES and THE GLASS SIDEBAR.
# This app turns it on in config/initializers/studio.rb, puts the switch on the root
# in layouts/application, tints it in its own colours in
# app/assets/tailwind/application.css, and keeps the game as it was: the docked army
# sheet stays solid (app/assets/stylesheets/game.css) and the game-over modal's
# buttons stay unlit. Each test goes red when one of those is removed. The browser
# proof of the paint is test/system/glass_surfaces_test.rb.
class GlassSurfaceAdoptionTest < ActionDispatch::IntegrationTest
  APP_CSS = Rails.root.join("app/assets/tailwind/application.css")
  GAME_CSS = Rails.root.join("app/assets/stylesheets/game.css")

  test "the initializer turns on the glass surfaces and the glass sidebar" do
    assert_equal :glass, Studio.surface_style
    assert_equal :glass, Studio.sidebar_style
  end

  test "a public page puts the glass switch on the root, beside its language" do
    get "/rules"
    assert_response :success
    assert_select "html[lang='en'][data-surface-style='glass']", count: 1
  end

  test "an admin page renders the glass sidebar panel" do
    log_in_as(User.create!(email: "admin@example.com", name: "Admin", role: "admin", username: "boss"))
    get "/admin/sign_ins"
    assert_response :success
    assert_select "html[data-surface-style='glass']", count: 1
    assert_select "[data-sidebar-glass-shell]"
  end

  test "the layout leaves the root bare when the surfaces are off" do
    Studio.surface_style = :default
    get "/rules"
    assert_select "html[data-surface-style]", count: 0
  ensure
    Studio.surface_style = :glass
  end

  # Cyvasse's colours, not the hub's: the blue ambient glow and the violet sidebar
  # are the engine's defaults, and this file replaces them.
  test "the app stylesheet tints the glass with Cyvasse's colours" do
    css = File.read(APP_CSS)
    assert_match(/html\[data-surface-style="glass"\]\s*\{[^}]*--surface-glass-ambient:[^}]*54 126 58/m, css,
                 "the light ambient page must use the success green in place of the engine's blue")
    assert_match(/html\.dark\[data-surface-style="glass"\]\s*\{[^}]*--lit-input:/m, css,
                 "the dark block must restate every --lit-* value the light block sets")
    assert_match(/^\[data-sidebar-glass-shell\]\s*\{[^}]*--glass-ink:\s*#2b2418/m, css)
    assert_match(/^\.dark \[data-sidebar-glass-shell\]\s*\{[^}]*--glass-fill:\s*rgb\(38 32 24/m, css)
    assert_match(/:not\(\.dark\) \.nav-shell \{\s*background-color: color-mix\(in srgb, var\(--color-page\) 90%/m, css,
                 "the light navbar must stay light over the dark hero and banners")
  end

  # The game keeps its look: the sheet over the board stays solid, and the
  # game-over modal's buttons stay the engine's plain filled ones.
  test "the docked army sheet and the game-over buttons opt out of the glass" do
    game = File.read(GAME_CSS)
    assert_match(/\.cyvasse-setup-controls \.cyvasse-army \{\s*--army-slot: 2\.75rem;\s*--surface-card-fill: var\(--color-surface\);\s*position: fixed;/m, game,
                 "the docked sheet floats over the board and must stay solid")
    css = File.read(APP_CSS)
    assert_match(/\.cyvasse-game-over \.btn \{[^}]*background-image: none;[^}]*box-shadow: none;/m, css)
    assert_match(/\.cyvasse-game-over \.btn::after \{\s*content: none;/m, css)
    modal = File.read(Rails.root.join("app/views/modals/_game_over.html.erb"))
    assert_includes modal, %(class="cyvasse-game-over )
  end
end
