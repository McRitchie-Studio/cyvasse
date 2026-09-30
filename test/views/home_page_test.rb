require "test_helper"

# [component] The front door (pages/index), rendered alone: Play Now, then
# Rules and Play a friend as smaller outlined buttons, over the piece gallery,
# whose slides offer each crop at 1x and 2x.
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
    assert_match %r{backgrounds/home/#{@gallery.first.slug}-\h+\.webp\z}, first_img["src"], "the 1x wide crop is the fallback"
    assert_wide_srcset @gallery.first.slug, first_img["srcset"]
    assert_equal "100vw", first_img["sizes"]
    portrait = first.at_css("source[media='(max-width: 640px)']")
    assert_portrait_srcset @gallery.first.slug, portrait["srcset"]
    assert_equal "100vw", portrait["sizes"]

    rest.each do |slide|
      slug = slide["data-piece"]
      img = slide.at_css("img")
      assert_not_includes slide["class"], "is-active", slug
      assert_equal "lazy", img["loading"], slug
      assert_nil img["src"], "#{slug} waits for its turn"
      assert_nil img["srcset"], "#{slug} waits for its turn"
      assert_match %r{backgrounds/home/#{slug}-\h+\.webp\z}, img["data-src"]
      assert_wide_srcset slug, img["data-srcset"]
      assert_equal "100vw", img["sizes"], slug
      source = slide.at_css("source[media='(max-width: 640px)']")
      assert_nil source["srcset"], slug
      assert_portrait_srcset slug, source["data-srcset"]
      assert_equal "100vw", source["sizes"], slug
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

  # The preload names the same srcset and sizes as the first slide, and no
  # href, so the browser preloads the file the slide picks and nothing else.
  test "only the first slide is preloaded, one crop per screen size, by the slide's own srcset" do
    @gallery = HomeGallery.slides(random: Random.new(1))
    render_home(user: nil)

    links = Nokogiri::HTML5.fragment(view.content_for(:head).to_s).css("link[rel=preload][as=image]")
    assert_equal 2, links.size
    links.each do |link|
      assert_nil link["href"], "no href: a browser with imagesrcset would ignore it, one without would fetch the wrong file"
      assert_equal "high", link["fetchpriority"]
      assert_equal "100vw", link["imagesizes"]
    end
    by_media = links.index_by { _1["media"] }
    slug = @gallery.first.slug
    assert_wide_srcset slug, by_media.fetch("(min-width: 641px)")["imagesrcset"]
    assert_portrait_srcset slug, by_media.fetch("(max-width: 640px)")["imagesrcset"]

    first = css_select("section.home-hero .home-slide").first
    assert_equal first.at_css("img")["srcset"], by_media.fetch("(min-width: 641px)")["imagesrcset"], "the preload is the slide's own set"
    assert_equal first.at_css("source")["srcset"], by_media.fetch("(max-width: 640px)")["imagesrcset"]
  end

  # Full bleed (task cyvasse-full-bleed-home): the hero is the layout's :hero
  # slot, not the page body inside <main>, and it is not a rounded card.
  test "the hero fills the :hero slot, square, with nothing left in the body" do
    view.define_singleton_method(:logged_in?) { false }
    view.define_singleton_method(:current_user) { nil }
    body = render template: "pages/index"

    assert_no_match(/home-hero/, body, "nothing of the hero inside <main>")
    hero = Nokogiri::HTML5.fragment(view.content_for(:hero).to_s).at_css("section.home-hero")
    assert hero, "the hero is in the :hero slot"
    assert_empty hero["class"].split.grep(/\A(rounded|mx-|px-|max-w-)/), "no card corners or gutters"
  end

  test "a signed-in player is named and not offered Sign in" do
    render_home(user: User.new(name: "Arya", email: "arya@example.test"))

    assert_select "p", /Signed in as/
    assert_select "a[href=?]", signin_path, 0
  end

  private

  # "<…/slug-<digest>.webp> 1800w, <…/slug-2x-<digest>.webp> 3600w"
  def assert_wide_srcset(slug, srcset)
    assert_match %r{\A\S+/backgrounds/home/#{slug}-\h+\.webp 1800w, \S+/backgrounds/home/#{slug}-2x-\h+\.webp 3600w\z}, srcset
  end

  def assert_portrait_srcset(slug, srcset)
    assert_match %r{\A\S+/backgrounds/home/#{slug}-mobile-\h+\.webp 720w, \S+/backgrounds/home/#{slug}-mobile-2x-\h+\.webp 1440w\z}, srcset
  end

  def render_home(user:)
    view.define_singleton_method(:logged_in?) { user.present? }
    view.define_singleton_method(:current_user) { user }
    body = render template: "pages/index"
    # The hero goes to the layout's :hero slot (full bleed, outside <main>),
    # so what the page shows is that slot plus its body.
    @rendered = view.content_for(:hero).to_s + body
  end
end
