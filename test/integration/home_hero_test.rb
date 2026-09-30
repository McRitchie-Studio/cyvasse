require "test_helper"

# [component] The front door's hero is full bleed (task
# cyvasse-full-bleed-home): the layout's :hero slot renders it outside
# <main>'s centred container, straight after the navbar, with no rounded card
# around it; other pages keep the padded container.
class HomeHeroTest < ActionDispatch::IntegrationTest
  test "the hero sits outside the page container, square and unpadded" do
    get root_path

    assert_select "body > section.home-hero", 1
    assert_select "main section.home-hero", 0
    hero = css_select("section.home-hero").first
    assert_empty hero.classes.grep(/\Arounded|\Amx-|\Apx-|\Amax-w-/), "no card corners or gutters"
    assert_select "section.home-hero .home-hero-scrim .max-w-2xl.mx-auto h1", "Cyvasse"
    assert_select "section.home-hero [data-leaderboard-card]", 1
    assert_select "section.home-hero .home-gallery-captions", 1

    main = css_select("main").first
    assert_includes main.classes, "max-w-7xl"
    assert_not_includes main.classes, "py-6", "no empty band under the hero"
  end

  test "a page without a hero keeps the padded container" do
    get rules_path

    assert_select "section.home-hero", 0
    assert_includes css_select("main").first.classes, "py-6"
  end
end
