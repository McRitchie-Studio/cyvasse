require "test_helper"

# [unit] In light mode the gold primary (#C08A2E) is 2.9:1 on the page, under
# WCAG AA's 4.5:1 for text. Links in the rules and about copy, and the pressed
# skin toggle, use the 700 shade there instead; this measures that shade on
# the two light surfaces those links sit on (the page, and a card) and
# checks the styles still use it. (The engine's deepest light inset, 4.48:1,
# carries none of them.)
class LightModeContrastTest < ActiveSupport::TestCase
  AA = 4.5

  setup do
    @theme = Studio::ThemeResolver.new(primary: Studio.theme_primary)
    @palette = @theme.primary_palette_vars
    light = @theme.light_mode_vars
    @light_surfaces = [ light.fetch("--color-page"), light.fetch("--color-surface") ]
  end

  test "the 700 shade clears AA on the light page and card, and the bare gold does not" do
    shade = @palette.fetch("--color-primary-700")
    @light_surfaces.each do |surface|
      assert_operator Studio::ColorScale.contrast_ratio(shade, surface), :>=, AA, "#{shade} on #{surface}"
    end
    assert_operator Studio::ColorScale.contrast_ratio(@palette.fetch("--color-primary"), @light_surfaces.first), :<, AA,
                    "if the gold itself passes, the light-mode override can go"
  end

  test "white on the 700 shade clears AA for the pressed skin toggle" do
    assert_operator Studio::ColorScale.contrast_ratio("#ffffff", @palette.fetch("--color-primary-700")), :>=, AA
  end

  test "light-mode links and the pressed toggle use the 700 shade" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    rule = css[/html:not\(\.dark\) \.rules-prose a,.*?\{(.*?)\}/m, 1]
    assert_match "--color-primary-700-rgb", rule.to_s, "light-mode prose links"
    assert_includes css[/html:not\(\.dark\) \.rules-prose a,.*?\{/m], "html:not(.dark) .about-page a"

    toggle = Rails.root.join("app/views/skins/_toggle.html.erb").read
    assert_includes toggle, "aria-pressed:bg-primary-700"
    assert_not_includes toggle, "aria-pressed:bg-primary "
  end
end
