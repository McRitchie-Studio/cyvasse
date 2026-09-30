require "test_helper"

# [component] The contract between game.css and the board controllers'
# setup scroll (task cyvasse-dock-landscape-tablet): each screen's setup
# layout names its fit in --setup-fit, which cyvasse/setup_fit reads, under
# the media query that picks it. A fit renamed on one side only would leave
# a phone or tablet with no setup scroll at all, which no desktop test sees.
class SetupFitStylesTest < ActiveSupport::TestCase
  CSS = Rails.root.join("app/assets/stylesheets/game.css").read
  FITS = {
    "bottom" => "@media (max-width: 1023px) and (orientation: portrait)",
    "side" => "@media (max-width: 1023px) and (orientation: landscape)",
    "page" => "@media (min-width: 1024px) and (hover: none) and (pointer: coarse)"
  }.freeze

  FITS.each do |fit, query|
    test "the #{fit} fit is named under #{query}" do
      start = CSS.index("#{query} {")
      assert start, "game.css has #{query}"
      block = CSS[start..].split(/^}/).first
      assert_includes block, "--setup-fit: #{fit};"
    end
  end

  test "the fits the stylesheet names are the fits the scroll knows" do
    named = CSS.scan(/--setup-fit:\s*([a-z]+);/).flatten.uniq.sort
    known = Rails.root.join("app/javascript/cyvasse/setup_fit.js").read[/\[("[a-z]+"(?:, "[a-z]+")*)\]\.includes\(fit\)/, 1]
    assert known, "setup_fit.js lists its fits"
    assert_equal named, known.scan(/"([a-z]+)"/).flatten.sort
  end

  test "a desktop with a mouse gets no fit" do
    refute_match(/@media \(min-width: 1024px\) \{[^}]*--setup-fit/m, CSS)
  end
end
