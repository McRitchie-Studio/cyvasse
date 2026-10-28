require "test_helper"

# [integration] The pages link the Tailwind build that application.css makes
# through studio-engine's host.css (task satellites-adopt-css-first-tailwind),
# and every /assets URL a page names is served. The build must carry one probe
# class for each thing it depends on (studio-engine README, "Tailwind", step 5):
#   .text-heading   the engine's theme tokens (engine.css's theme). This app's
#                   own views and game.css use it too (admin/conversations ...),
#                   so it proves the theme is imported, not any scan.
#   .btn-primary    the engine's component @utility layer. This app's own views
#                   use it (admin/conversations/index, chat/_thread ...), so it
#                   proves the layer is imported, not that the engine's views
#                   are scanned.
#   .animate-spin   the engine view scan (host.css's @source "../../../views").
#                   Only studio-engine's views name it (studio/modals/blocks/
#                   _processing_card, error_logs/index, style/_modals,
#                   components/_theme_toggle_morph, solana_sessions/
#                   phantom_callback); nothing else in this repo, and no engine
#                   CSS, component, helper or JavaScript declares it, so it
#                   compiles only when Tailwind reaches those views. If this
#                   app's code ever uses it, pick another engine-only class.
#   .spinner        the engine's motion layer (engine-motion.css). It is plain
#                   CSS, emitted on import alone: it proves the import, not any
#                   scan.
# Tailwind v4 scans this repo's test/ too. It skips Ruby # comments, so naming
# the classes here is safe, but it picks up a class written as a code literal:
# a literal probe in the code below would compile because this file names it,
# and pass whatever the engine scan does (proven in alex-build PR #9). So the
# code spells each probe as words joined with "-" at runtime.
class TailwindAssetsTest < ActionDispatch::IntegrationTest
  PROBES = [ %w[text heading], %w[btn primary], %w[animate spin], %w[spinner] ]
           .map { |words| words.join("-") }.freeze

  test "the home page names only assets that are served" do
    get root_path
    assert_response :success
    assert_every_asset_served
  end

  test "a signed-in page names only assets that are served" do
    log_in_as(User.create!(email: "tailwind@example.com", name: "Tailwind Probe", username: "tailwind_probe"))
    get matches_path
    assert_response :success
    assert_every_asset_served
  end

  test "the linked Tailwind build carries the engine's tokens, components, scanned views and motion" do
    get root_path
    href = asset_urls.find { |url| url.match?(%r{\A/assets/tailwind-[0-9a-f]+\.css\z}) }
    assert href, "the layout must link the Tailwind build"

    get href
    assert_response :success
    css = response.body.delete(" \n")
    PROBES.each do |probe|
      assert_includes css, ".#{probe}{", "the Tailwind build lost .#{probe}"
    end
  end

  private

  def asset_urls
    Nokogiri::HTML(response.body).css("link[href], script[src], img[src], source[src]")
            .map { |node| node["href"] || node["src"] }
            .select { |url| url.start_with?("/assets/") }
            .uniq
  end

  def assert_every_asset_served
    urls = asset_urls
    assert urls.any? { |url| url.start_with?("/assets/tailwind-") }, "the page must link the Tailwind build"
    urls.each do |url|
      get url
      assert_response :success, "#{url} is named by the page but not served"
    end
  end
end
