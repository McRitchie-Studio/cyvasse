require "test_helper"

# [unit] Cyvasse's colours against WCAG AA, 4.5:1 for normal-size text (task
# cyvasse-contrast-and-names). The brand gold (#C08A2E) is 3.04:1 under white
# and 2.9:1 as text on the light page; the engine's success green (#4BAF50) is
# 2.78:1 under white. So the gold CTA fill is the primary scale's 700 shade in
# both themes, gold text reads --cyvasse-gold-ink (700 light; the gold itself
# on the dark page, 400 on a dark card), and
# the green is config.theme_success, deeper. These measure the shades on every
# surface the engine theme emits, and check the stylesheet still uses them.
# test/system/contrast_test.rb measures the rendered page.
class LightModeContrastTest < ActiveSupport::TestCase
  AA = 4.5

  setup do
    @theme = Studio::ThemeResolver.new(Studio.theme_config)
    @palette = @theme.primary_palette_vars
    light = @theme.light_mode_vars
    dark = @theme.dark_mode_vars
    @light_surfaces = light.values_at("--color-page", "--color-surface", "--color-surface-alt")
    @dark_surfaces = dark.values_at("--color-page", "--color-surface", "--color-surface-alt", "--color-inset")
    @css = Rails.root.join("app/assets/tailwind/application.css").read
  end

  def ratio(ink, ground) = Studio::ColorScale.contrast_ratio(ink, ground)

  test "the bare gold fails AA as a fill and as light-mode text, so the overrides stay" do
    gold = @palette.fetch("--color-primary")
    assert_operator ratio("#ffffff", gold), :<, AA, "if white on the gold passes, the CTA override can go"
    assert_operator ratio(gold, @light_surfaces.first), :<, AA, "if the gold passes on the page, the light ink can go"
  end

  test "white on the 700 shade clears AA: the CTA fill and the pressed skin toggle" do
    assert_operator ratio("#ffffff", @palette.fetch("--color-primary-700")), :>=, AA
  end

  test "the gold ink clears AA on every light and every dark surface" do
    @light_surfaces.each do |surface|
      shade = @palette.fetch("--color-primary-700")
      assert_operator ratio(shade, surface), :>=, AA, "light ink #{shade} on #{surface}"
    end
    card = @theme.dark_mode_vars.fetch("--color-surface")
    (@dark_surfaces - [ card ]).each do |ground|
      gold = @palette.fetch("--color-primary")
      assert_operator ratio(gold, ground), :>=, AA, "the brand gold as dark ink on #{ground}"
    end
    assert_operator ratio(@palette.fetch("--color-primary"), card), :<, AA, "if the gold passes on a dark card, the card override can go"
    assert_operator ratio(@palette.fetch("--color-primary-400"), card), :>=, AA, "the dark card ink"
  end

  test "white on the success green clears AA, where the engine default does not" do
    assert_operator ratio("#ffffff", Studio.theme_success), :>=, AA, "btn-secondary fill #{Studio.theme_success}"
    assert_operator ratio("#ffffff", "#4BAF50"), :<, AA, "the engine default this overrides"
  end

  test "the stylesheet uses those shades" do
    root = @css[/^:root:root \{(.*?)\}/m, 1].to_s
    assert_match "--color-cta: var(--color-primary-700)", root
    assert_match "--cyvasse-gold-ink: var(--color-primary)", root
    assert_match "--cyvasse-gold-ink: var(--color-primary-400)", @css[/^html:root\.dark :is\(\.card, \.bg-surface\) \{(.*?)\}/m, 1].to_s
    assert_match "--cyvasse-gold-ink: var(--color-primary-700)", @css[/^html:root:not\(\.dark\) \{(.*?)\}/m, 1].to_s

    assert_match "color: var(--cyvasse-gold-ink)", @css[/^\.text-primary,\n\.hover\\:text-primary:hover \{(.*?)\}/m, 1].to_s
    assert_match "color: var(--cyvasse-gold-ink)", @css[/^\.rules-prose a,\n\.about-page a \{(.*?)\}/m, 1].to_s
    assert_match "color: var(--cyvasse-gold-ink)", @css[/^\.leaderboard-inline-cta strong \{(.*?)\}/m, 1].to_s
    refute_match "color: rgb(var(--color-primary-rgb))", @css, "gold text should read the ink, not the bare gold"

    toggle = Rails.root.join("app/views/skins/_toggle.html.erb").read
    assert_includes toggle, "aria-pressed:bg-primary-700"
    assert_not_includes toggle, "aria-pressed:bg-primary "
  end
end
