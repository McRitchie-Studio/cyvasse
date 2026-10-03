require "application_system_test_case"

# [e2e] The site footer's rows in a real browser (task
# cyvasse-footer-and-legal), at the five widths studio-engine's own footer
# spec measures. Cyvasse declares three link columns, so the engine's grid
# (docs/SITE_FOOTER.md) gives:
#
#   320, 390   the brand across the top; Play and Learn side by side under
#              it; Legal on a row of its own
#   768        the brand across the top; all three columns in one row
#   1024, 1280 the brand and all three columns in one row
#
# At every width nothing scrolls sideways and the contact email stays on one
# line. A desktop Chrome window will not shrink to a phone, so Chrome's device
# emulation sets the width, as in phone_width_test. SCREENSHOTS=1 saves each.
class SiteFooterRowsTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  EXPECTED_ROWS = {
    320 => [ %w[brand], %w[Play Learn], %w[Legal] ],
    390 => [ %w[brand], %w[Play Learn], %w[Legal] ],
    768 => [ %w[brand], %w[Play Learn Legal] ],
    1024 => [ %w[brand Play Learn Legal] ],
    1280 => [ %w[brand Play Learn Legal] ]
  }.freeze

  EXPECTED_ROWS.each do |width, rows|
    test "the footer's rows at #{width}px" do
      viewport!(width)
      visit rules_path
      assert_selector "footer[data-site-footer] .ftr-col", count: 3

      layout = footer_layout
      assert_equal width, layout["client"], "the viewport is #{width}px"
      assert_operator layout["scroll"], :<=, layout["client"], "no sideways scroll at #{width}px"
      assert_equal rows, rows_of(layout["boxes"]), "rows at #{width}px"
      assert_equal 1, layout["emailLines"], "the contact email stays on one line at #{width}px"
      assert_operator layout["emailRight"], :<=, width, "the contact email ends inside the page at #{width}px"
      assert_empty layout["mapRequests"], "no Leaflet or map tile was fetched"
      screenshot("footer-#{width}")
    end
  end

  private

  def viewport!(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: 900, deviceScaleFactor: 1, mobile: width < 768)
  end

  def footer_layout
    page.evaluate_script(<<~JS)
      (() => {
        const footer = document.querySelector("footer[data-site-footer]")
        const box = (el, name) => { const r = el.getBoundingClientRect(); return { name, top: Math.round(r.top + window.scrollY), left: Math.round(r.left) } }
        const boxes = [box(footer.querySelector(".ftr-brand"), "brand")]
          .concat([...footer.querySelectorAll(".ftr-col")].map((col) => box(col, col.querySelector(".ftr-heading").textContent.trim())))
        const email = footer.querySelector(".ftr-email a")
        const emailRect = email.getBoundingClientRect()
        const lineHeight = parseFloat(getComputedStyle(email).lineHeight) || emailRect.height
        return {
          boxes,
          client: document.documentElement.clientWidth,
          scroll: document.documentElement.scrollWidth,
          emailLines: Math.round(emailRect.height / lineHeight),
          emailRight: Math.round(emailRect.right),
          mapRequests: performance.getEntriesByType("resource").map((e) => e.name).filter((n) => /leaflet|openstreetmap/i.test(n))
        }
      })()
    JS
  end

  # Boxes whose tops are within a few pixels share a row.
  def rows_of(boxes)
    boxes.sort_by { |b| b["top"] }.chunk_while { |a, b| (b["top"] - a["top"]).abs <= 4 }
         .map { |row| row.sort_by { |b| b["left"] }.map { |b| b["name"] } }
  end

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    page.execute_script("document.querySelector('footer[data-site-footer]').scrollIntoView({ block: 'end' })")
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png"))
  end
end
