require "test_helper"

# [component] The front door (pages/index), rendered alone: Play Now, then
# Rules and Play a friend as smaller outlined buttons, over the action shot.
class HomePageTest < ActionView::TestCase
  setup { @live_leaderboard = [] }

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

  test "the hero sits on the game action shot under a black scrim" do
    render_home(user: nil)

    assert_select "section.home-hero img[data-home-background][alt=''][src*='cyvasse_home_background']"
    assert_select "section.home-hero .home-hero-scrim h1", "Cyvasse"
    assert_select "section.home-hero [data-leaderboard-card]"
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
