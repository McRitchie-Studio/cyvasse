require "application_system_test_case"

# [e2e] /rules in a real browser (tasks cyvasse-rules-page-refresh and
# cyvasse-rules-unit-card-layout): the unit cards run three a row on a wide
# screen and one a row on a phone, each a centred portrait column whose row
# mates stand the same height, its art large and bare (no parchment tile),
# neither width scrolls sideways, and the banner paints the crop meant for
# that screen.
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
    assert_centred_stack
    assert_bare_large_art
    assert_equal_heights_in_rows
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
    assert_centred_stack
    assert_bare_large_art
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

  # Art, name and every stat share one centre line, top to bottom, and the
  # Trebuchet's three trump icons have painted.
  def assert_centred_stack
    off = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#units .unit-card")].flatMap((card) => {
        const box = card.getBoundingClientRect()
        const mid = box.left + box.width / 2
        const parts = [card.querySelector(".unit-card-art"), card.querySelector(".unit-card-name"), ...card.querySelectorAll(".unit-stat")]
        const bad = []
        let bottom = -Infinity
        for (const el of parts) {
          const r = el.getBoundingClientRect()
          if (Math.abs(r.left + r.width / 2 - mid) > 2) bad.push(`${card.dataset.unit}: ${el.className} off centre`)
          if (r.top < bottom - 0.5) bad.push(`${card.dataset.unit}: ${el.className} not below the last`)
          bottom = r.bottom
        }
        for (const stat of card.querySelectorAll(".unit-stat")) {
          const [dt, dd] = [stat.querySelector("dt"), stat.querySelector("dd")]
          if (dd.getBoundingClientRect().top < dt.getBoundingClientRect().bottom - 0.5) bad.push(`${card.dataset.unit}: ${stat.dataset.stat} value not under its label`)
        }
        return bad
      })
    JS
    assert_empty off
    # The trebuchet trumps only the dragon since the new stats of September 29, 2026.
    icons = all("#unit-trebuchet .unit-trump-icon", minimum: 1)
    assert_equal [ "Trumps Dragon" ], icons.map { _1[:alt] }
    scroll_to find("#unit-trebuchet") # the icons load lazily
    painted = "[...document.querySelectorAll('#unit-trebuchet .unit-trump-icon')].every((img) => img.complete && img.naturalWidth > 0)"
    assert(Capybara.using_wait_time(5) do
      page.document.synchronize do
        raise Capybara::ExpectationNotMet, "trump icons not painted" unless page.evaluate_script(painted)
        true
      end
    end, "every trump icon painted")
  end

  # Alex's follow-up: every card's art stands at least 1.5x the old 88px tile
  # (8.25rem = 132px) and stays square inside its card, with no fill or
  # border behind it or the trump icons in the light theme; the dark theme
  # lights a glow and a rim instead. Both themes are read on one page load.
  def assert_bare_large_art
    report = page.evaluate_script(<<~JS)
      (() => {
        const root = document.documentElement, wasDark = root.classList.contains("dark")
        root.classList.remove("dark")
        const bare = (el) => { const s = getComputedStyle(el); return s.backgroundColor === "rgba(0, 0, 0, 0)" && s.backgroundImage === "none" && parseFloat(s.borderTopWidth) === 0 }
        const bad = []
        for (const card of document.querySelectorAll(".unit-card")) {
          const art = card.querySelector(".unit-card-art"), box = card.getBoundingClientRect(), r = art.getBoundingClientRect()
          if (Math.abs(r.width - r.height) > 0.5) bad.push(`${card.dataset.unit}: art ${r.width}x${r.height} not square`)
          if (card.closest("#units") && r.width < 131.5) bad.push(`${card.dataset.unit}: art ${r.width}px, under 1.5x`)
          if (r.left < box.left - 0.5 || r.right > box.right + 0.5) bad.push(`${card.dataset.unit}: art spills its card`)
          if (!bare(art)) bad.push(`${card.dataset.unit}: art has a tile`)
          for (const icon of card.querySelectorAll(".unit-trump-icon")) if (!bare(icon)) bad.push(`${card.dataset.unit}: trump icon has a tile`)
        }
        root.classList.add("dark")
        const art = document.querySelector("#unit-trebuchet .unit-card-art")
        const dark = [getComputedStyle(art).backgroundImage, getComputedStyle(art.querySelector("img")).filter,
                      getComputedStyle(document.querySelector("#unit-trebuchet .unit-trump-icon")).filter]
        root.classList.toggle("dark", wasDark)
        return { bad, dark }
      })()
    JS
    assert_empty report["bad"]
    glow, art_rim, icon_rim = report["dark"]
    assert_match(/radial-gradient/, glow, "dark theme: a glow behind the art")
    assert_match(/drop-shadow/, art_rim, "dark theme: a rim on the art")
    assert_match(/drop-shadow/, icon_rim, "dark theme: a rim on the trump icons")
  end

  def assert_equal_heights_in_rows
    heights = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#units .unit-grid")].map((grid) => {
        const rows = new Map()
        for (const card of grid.querySelectorAll(".unit-card")) {
          const r = card.getBoundingClientRect()
          rows.set(Math.round(r.top), [...(rows.get(Math.round(r.top)) || []), Math.round(r.height)])
        }
        return [...rows.values()]
      }).flat()
    JS
    heights.each { |row| assert_equal 1, row.uniq.size, "cards in a row stand level: #{row}" }
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
