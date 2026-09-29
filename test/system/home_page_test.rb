require "application_system_test_case"

# [e2e] The front door in a real browser: the action shot is painted under a
# black scrim, Rules leads to /rules, and a phone gets no sideways scroll.
# SCREENSHOTS=1 saves each view to tmp/screenshots.
class HomePageSystemTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "the background is present, the text sits on a dark scrim, and Rules opens the rules" do
    visit root_path

    img = find("section.home-hero .home-slide.is-active img[data-home-background]", visible: :all)
    assert page.evaluate_script("arguments[0].complete && arguments[0].naturalWidth > 0", img), "the first action shot loaded"
    alpha = page.evaluate_script("getComputedStyle(document.querySelector('.home-hero-scrim')).backgroundColor")
    assert_match(/\Argba?\(0, 0, 0, 0\.[67]\d*\)\z/, alpha, "a black scrim of at least 60%")
    assert_equal "rgb(255, 255, 255)", page.evaluate_script("getComputedStyle(document.querySelector('.home-hero h1')).color")
    assert_selector ".home-hero [data-leaderboard-card]"
    assert_no_link "Play the computer"
    screenshot("desktop")

    click_on "Rules"
    assert_current_path rules_path
  end

  test "the front door fits a 390px phone" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit root_path
    assert_selector "section.home-hero a", text: "Play a friend"

    scroll, client = page.evaluate_script("[document.documentElement.scrollWidth, document.documentElement.clientWidth]")
    assert_equal 390, client
    assert_operator scroll, :<=, client, "no sideways scroll at 390px"
    screenshot("phone")
  end

  # [e2e] The piece gallery behind the hero: it crossfades to the next piece,
  # loading each slide's art only as its turn comes, and never moves the page.
  [ [ "desktop", 1400, 1100 ], [ "phone", 390, 844 ] ].each do |name, width, height|
    test "the gallery advances through the pieces on a #{name}" do
      emulate(width:, height:)
      visit root_path
      gallery = find("section.home-hero[data-home-gallery-state=playing]")
      first = gallery["data-home-gallery-piece"]
      assert_selector ".home-slide.is-active", count: 1, visible: :all
      assert_selector ".home-slide.is-active[data-piece='#{first}'] img[data-home-background]", visible: :all
      assert_selector ".home-slide-caption.is-active", count: 1, visible: :all
      box = hero_box

      page.execute_script("document.querySelector('.home-hero').dataset.homeGalleryIntervalValue = '400'")
      assert_no_selector "section.home-hero[data-home-gallery-piece='#{first}']", wait: 10
      second = gallery["data-home-gallery-piece"]
      assert_selector ".home-slide.is-active", count: 1, visible: :all
      active = find(".home-slide.is-active", visible: :all)
      assert_equal second, active["data-piece"]
      assert page.evaluate_script("(img => img.complete && img.naturalWidth > 0)(document.querySelector('.home-slide.is-active img'))"),
        "the slide shown has its art"
      src = page.evaluate_script("document.querySelector('.home-slide.is-active img').currentSrc")
      assert_match(width <= 640 ? %r{/#{second}-mobile-\h+\.webp\z} : %r{/#{second}-\h+\.webp\z}, src, "the #{name} crop")
      assert_equal "The #{Piece.all.find { _1.slug == second }.name}", find(".home-slide-caption.is-active", visible: :all).text(:all).strip
      assert_equal box, hero_box, "the hero did not move or resize"

      # A slide more is on its way; the rest have not been asked for.
      unloaded = page.evaluate_script("[...document.querySelectorAll('.home-slide img')].filter((img) => img.dataset.src).length")
      assert_operator unloaded, :>=, HomeGallery::SLIDES.size - 4
      assert_operator unloaded, :<=, HomeGallery::SLIDES.size - 2

      scroll, client = page_widths
      assert_operator scroll, :<=, client, "no sideways scroll"
      screenshot("gallery-#{name}")
    end

    test "reduced motion holds the gallery on one still on a #{name}" do
      emulate(width:, height:)
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      visit root_path
      gallery = find("section.home-hero[data-home-gallery-state=still]")
      first = gallery["data-home-gallery-piece"]
      assert_not_empty first
      page.execute_script("document.querySelector('.home-hero').dataset.homeGalleryIntervalValue = '100'")
      sleep 1.2 # ten intervals, if anything were ticking
      assert_equal first, gallery["data-home-gallery-piece"]
      assert_selector ".home-slide.is-active[data-piece='#{first}']", count: 1, visible: :all
      assert_equal "0s", page.evaluate_script("getComputedStyle(document.querySelector('.home-slide')).transitionDuration")
      unloaded = page.evaluate_script("[...document.querySelectorAll('.home-slide img')].filter((img) => img.dataset.src).length")
      assert_equal HomeGallery::SLIDES.size - 1, unloaded, "no other slide is fetched"
    end
  end

  private

  def emulate(width:, height:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 640)
  end

  def hero_box
    page.evaluate_script("(r => [r.x, r.y, r.width, r.height].map(Math.round))(document.querySelector('.home-hero').getBoundingClientRect())")
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/home-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
