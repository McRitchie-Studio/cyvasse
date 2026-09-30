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

  # One, two, then three a row, in a wrapping flex row so a short last row
  # sits centred (Alex, 2026-09-29); the browser check is in
  # test/system/rules_page_layout_test.rb.
  test "every unit class lays its cards out one, two, then three a row, a short row centred" do
    render template: "pages/rules"

    grids = css_select("#units .unit-class .unit-grid")
    assert_equal Rulebook.classes.size, grids.size
    css = Rails.root.join("app/assets/tailwind/application.css").read
    grid = css[/^\.unit-grid \{.*?\}/m]
    assert_match(/display: flex;/, grid)
    assert_match(/flex-wrap: wrap;/, grid)
    assert_match(/justify-content: center;/, grid)
    assert_match(%r{@media \(min-width: 40rem\) \{\s*\.unit-grid > \.unit-card \{\s*flex-basis: calc\(\(100% - 1rem\) / 2\);}, css)
    assert_match(%r{@media \(min-width: 64rem\) \{\s*\.unit-grid > \.unit-card \{\s*flex-basis: calc\(\(100% - 2rem\) / 3\);}, css)
    total = Rulebook.classes.sum { _1.units.size }
    assert_select "#units .unit-grid > article.unit-card > .unit-card-body", total
    assert_select "#units .unit-card-body > .unit-card-name", total
    assert_select "#units .unit-card-body > dl.unit-stats", total
  end

  # [component] Alex's wireframe (cyvasse-rules-unit-card-layout): one
  # centred column, art over name over stats, each stat a label above its
  # value, and the trumps drawn as the trumped pieces' art.
  test "a unit card stacks art, name and labelled stats, with trumps as piece art" do
    render partial: "pages/unit_card", locals: { unit: Rulebook.fetch("trebuchet"), id: "unit-trebuchet" }

    card = css_select("article#unit-trebuchet.unit-card[data-unit=trebuchet]").sole
    body = card.at_css("> .unit-card-body")
    assert_equal %w[figure h4 dl], body.element_children.map(&:name), "art, then name, then stats"
    assert_equal "Trebuchet", body.at_css("h4.unit-card-name").text.strip
    assert_equal "Trebuchet", body.at_css("figure.unit-card-art img")["alt"]
    refute_includes body.at_css("figure.unit-card-art")["class"].split, "piece-tile", "the art sits bare, off the parchment tile"

    stats = body.css("dl.unit-stats > div.unit-stat")
    assert_equal %w[range strength movement trump], stats.map { _1["data-stat"] }, "a range unit leads with Range"
    stats.each do |stat|
      assert_equal %w[dt dd], stat.element_children.map(&:name), "#{stat["data-stat"]}: label above value"
    end
    assert_equal [ %w[Range 4], %w[Strength 1], %w[Movement 0] ],
                 stats.first(3).map { |stat| [ stat.at_css("dt").text.strip, stat.at_css("dd").text.strip ] }
    assert_includes stats.first.at_css("dd")["class"].split, "text-xl", "the value reads larger than its label"

    icons = stats.last.css("dd.unit-trumps img.unit-trump-icon")
    # Since the new stats of September 29, 2026 the trebuchet trumps only the dragon.
    assert_equal [ "Trumps Dragon" ], icons.map { _1["alt"] }
    assert_equal icons.map { _1["alt"] }, icons.map { _1["title"] }
    assert_equal %w[dragon], icons.map { _1["data-trump"] }
    icons.each { |img| assert_match %r{/pieces/vector/#{img["data-trump"]}-}, img["src"], "the reader's skin" }
    assert_empty css_select(".unit-stat-marked"), "the Units list marks nothing"
  end

  # [component] Alex, 2026-09-29: "On the Range units put the Range ahead of
  # Strength, as Range is the most important in this class."
  test "range units list Range, Strength, Movement, Trump; every other unit Strength first" do
    Rulebook.classes.flat_map(&:units).each do |unit|
      card = Nokogiri::HTML5.fragment(render(partial: "pages/unit_card", locals: { unit: }))
      expected = unit.range ? %w[range strength movement trump] : %w[strength movement trump]
      assert_equal expected, card.css("dl.unit-stats > div.unit-stat").map { _1["data-stat"] }, unit.slug
    end
    assert_equal %w[crossbowman catapult trebuchet], Rulebook.classes.flat_map(&:units).select(&:range).map(&:slug)
  end

  # [component] Alex, 2026-09-29: "Let's change this: straight lines". The
  # Dragon's movement reads short, at a number's size, with the full meaning
  # as its title and for screen readers.
  test "the dragon's movement is a short value with an accessible full description" do
    render partial: "pages/unit_card", locals: { unit: Rulebook.fetch("dragon") }

    dd = css_select("dd[data-stat=movement]").sole
    assert_equal "Moves any distance in a straight line", dd["title"]
    assert_equal "Straight lines", dd.at_css("span[aria-hidden=true]").text
    assert_equal "Moves any distance in a straight line", dd.at_css("span.sr-only").text
    assert_no_match(/Moves in a straight line/, rendered)
    assert_includes dd["class"].split, "text-xl"
  end

  test "a unit that trumps nothing shows a dash, and the pencil skin reaches the trump icons" do
    view.define_singleton_method(:current_skin) { :pencil }
    render partial: "pages/unit_card", locals: { unit: Rulebook.fetch("spearman") }
    assert_select "dd[data-stat=trump]", text: "—"
    assert_select "dd[data-stat=trump] img", 0

    render partial: "pages/unit_card", locals: { unit: Rulebook.fetch("king") }
    assert_select "dd[data-stat=trump][data-skin=pencil] img[alt='Trumps Dragon'][src*='/pieces/pencil/dragon-']", 1
    assert_select "figure.unit-card-art[data-skin=pencil] > img[src*='/pieces/pencil/king-']", 1
  end

  test "a special rules card marks the stat its rule is about, label and value together" do
    render partial: "pages/unit_card", locals: { unit: Rulebook.fetch("rabble"), highlight: %i[trump] }

    assert_select ".unit-stat.unit-stat-marked", 1
    assert_select ".unit-stat-marked[data-stat=trump] > dt", text: "Trump"
    assert_select ".unit-stat-marked[data-stat=trump] > dd img[alt='Trumps King']", 1
  end

  test "the unit card CSS is one centred column, with no side-by-side container query left" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    body = css[/^\.unit-card-body \{.*?\}/m]
    assert_match(/flex-direction: column;/, body)
    assert_match(/align-items: center;/, body)
    assert_match(/text-align: center;/, body)
    assert_no_match(/@container/, css, "the art-beside-name layout is gone")
    assert_match(/^\.unit-card \{\s*height: 100%;/, css, "cards fill their row")
  end

  # [component] Alex's follow-up: no white tile behind the art or the trump
  # icons, the art 1.5x the old 5.5rem tile, and a dark-theme glow and rim
  # (the army dock's) so dark ink still reads on a dark card.
  test "the unit card art and trump icons sit bare, the art at 8.25rem, with a dark-theme glow" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    art = css[/^\.unit-card-art \{.*?\}/m]
    icon = css[/^\.unit-trump-icon \{.*?\}/m]
    assert_match(/width: min\(8\.25rem, 100%\);/, art, "1.5x the old 5.5rem, capped at the card")
    [ art, icon ].each do |rule|
      assert_no_match(/background|border:/, rule, "no tile behind #{rule[/\A\S+/]}")
    end
    assert_match(/^html\.dark \.unit-card-art \{\s*background-image: radial-gradient/, css)
    assert_match(/^html\.dark \.unit-card-art img,\s*html\.dark \.unit-trump-icon \{\s*filter: drop-shadow/, css)
    assert_match(/^html\.dark \.unit-card \[data-skin="pencil"\] > img \{\s*filter: drop-shadow/, css)
    built = Rails.root.join("app/assets/builds/tailwind.css")
    assert_includes built.read, "lg\\:grid-cols-3", "Tailwind emits the thirds utility" if built.exist?
  end
end
