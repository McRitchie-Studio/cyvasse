require "application_system_test_case"

# [e2e] /rules in a real browser (task cyvasse-rules-page-refresh): the unit
# cards run three a row on a wide screen and one a row on a phone, neither
# scrolls sideways, and the banner paints the crop meant for that screen.
# Chrome's device emulation sets the width, since a desktop window will not
# shrink to a phone (phone_width_test.rb).
class RulesPageLayoutTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "three unit cards a row at 1440px, with the wide banner crop" do
    screen!(1440, 900, mobile: false)
    visit rules_path

    rows = card_rows
    assert_equal [ 3 ], rows.fetch("vanguard").map(&:size), "Rabble, Spearman and Elephant share a row"
    assert_equal [ 3 ], rows.fetch("range").map(&:size)
    assert_equal [ 3 ], rows.fetch("unique").map(&:size)
    assert_equal [ 2 ], rows.fetch("cavalry").map(&:size)
    assert_no_sideways_scroll 1440
    assert_card_text_fits
    assert_banner_crop "capture-the-king-"
  end

  test "one unit card a row at 390px, with the phone banner crop" do
    screen!(390, 844, mobile: true)
    visit rules_path

    card_rows.each do |unit_class, rows|
      assert rows.all? { _1.size == 1 }, "#{unit_class}: every card on its own row"
    end
    assert_no_sideways_scroll 390
    assert_card_text_fits
    assert_banner_crop "capture-the-king-mobile-"
  end

  private

  def screen!(width, height, mobile:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height:, deviceScaleFactor: 1, mobile:)
  end

  # { "vanguard" => [[name, name, name]], ... }: each class's cards grouped
  # into rows by their top edge.
  def card_rows
    assert_selector "#units .unit-card", count: Rulebook.classes.sum { _1.units.size }
    page.evaluate_script(<<~JS)
      Object.fromEntries([...document.querySelectorAll("#units .unit-class")].map((section) => {
        const rows = new Map()
        for (const card of section.querySelectorAll(".unit-card")) {
          const top = Math.round(card.getBoundingClientRect().top)
          rows.set(top, [...(rows.get(top) || []), card.dataset.unit])
        }
        return [section.id.replace("class-", ""), [...rows.values()]]
      }))
    JS
  end

  def assert_no_sideways_scroll(width)
    widths = page.evaluate_script("[document.documentElement.scrollWidth, document.body.scrollWidth]")
    assert widths.all? { _1 <= width }, "the page is #{widths.max}px wide on a #{width}px screen"
  end

  # No card's name or stats spill past the card (so "Light Horse" and the
  # Trebuchet's three-unit trump list stay whole).
  def assert_card_text_fits
    spills = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#units .unit-card")].flatMap((card) => {
        const box = card.getBoundingClientRect()
        return [...card.querySelectorAll(".unit-card-name, .unit-stats dt, .unit-stats dd")].filter((el) => {
          const r = el.getBoundingClientRect()
          return r.right > box.right + 0.5 || r.left < box.left - 0.5 || el.scrollWidth > el.clientWidth + 1
        }).map((el) => `${card.dataset.unit}: ${el.textContent.trim()}`)
      })
    JS
    assert_empty spills
  end

  def assert_banner_crop(prefix)
    src = nil
    assert(Capybara.using_wait_time(5) do
      page.document.synchronize do
        src = page.evaluate_script("(() => { const img = document.querySelector('header.page-banner img'); return img.complete && img.naturalWidth > 0 ? img.currentSrc : null })()")
        raise Capybara::ExpectationNotMet, "banner not loaded" unless src
        true
      end
    end)
    assert_match %r{/backgrounds/rules/#{prefix}\h+\.webp\z}, src
  end
end
