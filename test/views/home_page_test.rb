require "test_helper"

# [component] The front door (pages/index), rendered alone: Play Now, then
# Rules and Play a friend as smaller outlined buttons, over the piece gallery.
class HomePageTest < ActionView::TestCase
  setup do
    @live_leaderboard = []
    @gallery = HomeGallery.slides
  end

  test "Play Now leads; Rules and Play a friend are the outlined secondaries" do
    render_home(user: nil)

    assert_select "form[action=?] button.btn-primary", live_seeks_path, "Play Now"
    assert_select "a.btn.home-secondary-btn[href=?]", rules_path, "Rules"
    assert_select "a.btn.home-secondary-btn[href=?]", matches_path, "Play a friend"
    assert_select "a.home-secondary-btn.btn-lg", 0, "secondaries are smaller than Play Now"
    assert_select "a.btn-secondary", 0, "no filled secondaries"
  end

  # The green label was ~3:1 over the scrimmed art; white clears WCAG AA.
  test "the outlined secondaries carry a white label, not the green" do
    render_home(user: nil)

    assert_select "a.home-secondary-btn", 3
    assert_select "a.home-secondary-btn:not(.text-white)", 0, "every secondary label is white"

    # An unlayered colour on the class would outrank the text-white utility.
    css = Rails.root.join("app/assets/tailwind/application.css").read
    rules = css.scan(/^\.home-secondary-btn[^{]*\{[^}]*\}/)
    assert_not_empty rules
    rules.each { |rule| assert_no_match(/(?<![-\w])color\s*:/, rule, "no label colour in: #{rule}") }
  end

  test "no Play the computer button, and the copy does not offer one" do
    render_home(user: nil)

    assert_select "section.home-hero a[href=?]", play_path, 0
    assert_no_match(/play the computer/i, rendered)
  end

  test "the hero sits on the piece gallery under a black scrim" do
    render_home(user: nil)

    assert_select "section.home-hero[data-controller='home-gallery'] .home-gallery[aria-hidden='true'] img[data-home-background][alt='']"
    assert_select "section.home-hero .home-hero-scrim h1", "Cyvasse"
    assert_select "section.home-hero [data-leaderboard-card]"
  end

  test "the gallery renders one slide per piece, the first eager and the rest deferred" do
    @gallery = HomeGallery.slides(random: Random.new(3))
    render_home(user: nil)

    slides = css_select("section.home-hero .home-slide[data-home-gallery-target='slide']")
    assert_equal Piece.all.map(&:slug).sort, slides.map { _1["data-piece"] }.sort, "one slide per piece"
    assert_equal @gallery.map(&:slug), slides.map { _1["data-piece"] }, "in the gallery's order"

    first, *rest = slides
    assert_includes first["class"], "is-active"
    first_img = first.at_css("img")
    assert_equal "eager", first_img["loading"]
    assert_equal "high", first_img["fetchpriority"]
    assert_match %r{backgrounds/home/#{@gallery.first.slug}-\h+\.webp\z}, first_img["src"]
    assert_match %r{backgrounds/home/#{@gallery.first.slug}-mobile-\h+\.webp\z}, first.at_css("source[media='(max-width: 640px)']")["srcset"]

    rest.each do |slide|
      slug = slide["data-piece"]
      img = slide.at_css("img")
      assert_not_includes slide["class"], "is-active", slug
      assert_equal "lazy", img["loading"], slug
      assert_nil img["src"], "#{slug} waits for its turn"
      assert_match %r{backgrounds/home/#{slug}-\h+\.webp\z}, img["data-src"]
      source = slide.at_css("source[media='(max-width: 640px)']")
      assert_nil source["srcset"], slug
      assert_match %r{backgrounds/home/#{slug}-mobile-\h+\.webp\z}, source["data-srcset"]
    end
    # Every slide holds the same box, so none can shift the page as it lands.
    slides.each { |slide| assert_equal [ "1800", "900" ], slide.at_css("img").then { [ _1["width"], _1["height"] ] } }
  end

  test "each slide names its piece in a quiet caption, only the first on show" do
    @gallery = HomeGallery.slides(random: Random.new(5))
    render_home(user: nil)

    captions = css_select("section.home-hero .home-gallery-captions[aria-hidden='true'] .home-slide-caption")
    assert_equal @gallery.map { "The #{_1.piece.name}" }, captions.map { _1.text.strip }
    assert_equal [ true ] + [ false ] * (captions.size - 1), captions.map { _1["class"].include?("is-active") }
  end

  test "only the first slide is preloaded, one crop per screen size" do
    @gallery = HomeGallery.slides(random: Random.new(1))
    render_home(user: nil)

    preloads = view.content_for(:head).scan(/<link rel="preload" as="image" href="([^"]+)" media="([^"]+)"/)
    assert_equal 2, preloads.size
    slug = @gallery.first.slug
    assert_match %r{/#{slug}-\h+\.webp\z}, preloads.to_h.invert.fetch("(min-width: 641px)")
    assert_match %r{/#{slug}-mobile-\h+\.webp\z}, preloads.to_h.invert.fetch("(max-width: 640px)")
  end

  test "a signed-in player is named and not offered Sign in" do
    render_home(user: User.new(name: "Arya", email: "arya@example.test"))

    assert_select "p", /Signed in as/
    assert_select "a[href=?]", signin_path, 0
  end

  private

  def render_home(user:)
    view.define_singleton_method(:logged_in?) { user.present? }
    view.define_singleton_method(:current_user) { user }
    render template: "pages/index"
  end
end
