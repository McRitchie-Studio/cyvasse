require "test_helper"

# [component] /rules (pages/rules), rendered alone: the banner is the current
# board captured by the rules scene of test/capture/home_gallery_capture.rb,
# with a phone crop and a preload, and the Units list lays its cards out in
# thirds on a wide screen (task cyvasse-rules-page-refresh).
class RulesPageTest < ActionView::TestCase
  IMAGES = Rails.root.join("app/assets/images")
  RULES_DIR = IMAGES.join("backgrounds/rules")

  setup do
    @unit_classes = Rulebook.classes
    view.define_singleton_method(:current_skin) { PieceSkinPreference::DEFAULT }
    view.define_singleton_method(:current_user) { nil }
  end

  test "the banner is the rules capture, eager and high priority, with a phone crop" do
    render template: "pages/rules"

    img = css_select("header.page-banner picture img").sole
    assert_match %r{backgrounds/rules/capture-the-king-\h+\.webp\z}, img["src"]
    assert_equal "", img["alt"], "decorative"
    assert_equal "eager", img["loading"]
    assert_equal "high", img["fetchpriority"]
    assert_equal %w[1800 600], [ img["width"], img["height"] ]
    assert_select "header.page-banner picture source[media='(max-width: 640px)'][srcset*='backgrounds/rules/capture-the-king-mobile-']", 1
    assert_select "header.page-banner .page-banner-scrim h1", "Rules"
    assert_select "header.page-banner .page-banner-scrim p", "The goal of Cyvasse is to capture your opponent's king."
    assert_no_match(/cyvasse_rules_background/, rendered, "the legacy screenshot is gone")
  end

  test "both banner crops are preloaded, one per screen size" do
    render template: "pages/rules"

    preloads = view.content_for(:head).scan(/<link rel="preload" as="image" href="([^"]+)" media="([^"]+)" fetchpriority="high">/)
    assert_equal 2, preloads.size
    by_media = preloads.to_h.invert
    assert_match %r{/capture-the-king-\h+\.webp\z}, by_media.fetch("(min-width: 641px)")
    assert_match %r{/capture-the-king-mobile-\h+\.webp\z}, by_media.fetch("(max-width: 640px)")
  end

  test "both crops are on disk as WebP under 150 KB, and nothing else" do
    %w[capture-the-king.webp capture-the-king-mobile.webp].each do |name|
      path = RULES_DIR.join(name)
      assert path.file?, name
      assert_equal "RIFF", File.binread(path, 4), name
      assert_equal "WEBP", File.binread(path, 4, 8), name
      assert_operator File.size(path), :<=, 150.kilobytes, name
    end
    assert_equal %w[capture-the-king-mobile.webp capture-the-king.webp], Dir.children(RULES_DIR).sort
    assert_not IMAGES.join("backgrounds/cyvasse_rules_background.png").exist?, "the legacy screenshot is deleted"
  end

  test "the capture script stages the rules scene and a rake task runs it" do
    script = Rails.root.join("test/capture/home_gallery_capture.rb").read
    assert_match(/^  RULES = \{/, script)
    assert_match(/test "capture the rules banner"/, script)
    assert_match(/task :capture_rules_hero/, Rails.root.join("lib/tasks/home_gallery.rake").read)
  end

  test "every unit class lays its cards out one, two, then three a row" do
    render template: "pages/rules"

    grids = css_select("#units .unit-class .unit-grid")
    assert_equal Rulebook.classes.size, grids.size
    grids.each do |grid|
      classes = grid["class"].split
      assert_includes classes, "grid"
      assert_includes classes, "sm:grid-cols-2"
      assert_includes classes, "lg:grid-cols-3"
    end
    total = Rulebook.classes.sum { _1.units.size }
    assert_select "#units .unit-grid > article.unit-card > .unit-card-body", total
    assert_select "#units .unit-card-body > .unit-card-name", total
    assert_select "#units .unit-card-body > dl.unit-stats", total
  end

  test "a unit card lays itself out by its own width, stacking its stats when narrow" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    assert_match(/^\.unit-card \{\s*container-type: inline-size;/, css)
    narrow = css[/@container \(max-width: 16rem\) \{.*?\n\}/m]
    assert narrow, "a narrow-card container query"
    assert_match(/grid-template-areas: "art name" "stats stats"/, narrow)
    built = Rails.root.join("app/assets/builds/tailwind.css")
    assert_includes built.read, "lg\\:grid-cols-3", "Tailwind emits the thirds utility" if built.exist?
  end
end
