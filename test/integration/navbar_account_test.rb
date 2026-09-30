require "test_helper"

# [component] The signed-in navbar, rendered on a real page from
# studio-engine's own components/_user_nav: Cyvasse keeps no copy of it since
# the engine took the name and the sign-in label as config (0.80.0,
# config/initializers/studio.rb; task cyvasse-navbar-config-switch). On a phone it shows one theme toggle, not one in each bar, and the
# avatar alone; the name and the avatar are one link, so one tab stop. The
# name is the player's public name (User#player_name), as everywhere else.
#
# Visibility is read from the classes: an element is off on a phone when it or an
# ancestor carries `hidden`, and off on a desktop when one carries `md:hidden`
# or a `hidden` that no `md:flex` undoes. test/system/contrast_test.rb looks
# at the same navbar in a browser at 390px.
class NavbarAccountTest < ActionDispatch::IntegrationTest
  setup do
    @guest = User.create_guest!(rng: Random.new(7))
    @guest.update!(email: "guest-navbar@example.com")
    log_in_as(@guest)
    get root_path
    assert_response :success
  end

  test "one theme toggle on a phone, and one on a desktop" do
    toggles = css_select("header[data-pin=nav] button[title='Toggle theme']")
    assert_equal 2, toggles.size, "the phone row's and the desktop bar's"

    assert_equal 1, toggles.count { |toggle| shown_on_phone?(toggle) }, "one toggle in a phone's tab order"
    assert_equal 1, toggles.count { |toggle| shown_on_desktop?(toggle) }, "one toggle in a desktop's tab order"
  end

  test "the link sidebar opens from the navbar on a phone and on a desktop" do
    triggers = css_select("header[data-pin=nav] [data-link-sidebar-trigger]")
    assert_equal 1, triggers.count { |trigger| shown_on_phone?(trigger) }, "the phone row's sidebar button"
    assert_equal 1, triggers.count { |trigger| shown_on_desktop?(trigger) }, "the desktop bar's sidebar button (the engine's extra_icons_html)"
  end

  test "the name and the avatar are one link to the profile" do
    links = css_select("header[data-pin=nav] a[href='#{profile_path}']")
    assert_equal 1, links.size, "one tab stop to the profile"

    link = links.first
    assert_equal @guest.player_name, link.at_css("[data-nav-name]").text.strip
    assert_equal "true", link.at_css("[aria-hidden]")["aria-hidden"], "the avatar adds nothing to the link's name"
  end

  test "on a phone the name is screen-reader text, so it never truncates on screen" do
    wrapper = css_select("header[data-pin=nav] [data-nav-name]").first.parent
    assert_includes wrapper["class"].split, "sr-only"
    assert_includes wrapper["class"].split, "md:not-sr-only"
  end

  test "the navbar shows the name the rest of the game shows" do
    assert_match(/\AGuest_\d{4}\z/, @guest.player_name)
    assert_select "header[data-pin=nav] [data-nav-name]", text: @guest.player_name
    assert_select "header[data-pin=nav]", text: /#{Regexp.escape(@guest.name)}/, count: 0
  end

  test "the partial is the engine's, not a Cyvasse copy" do
    refute_path_exists Rails.root.join("app/views/components/_user_nav.html.erb")
    template = ApplicationController.new.lookup_context.find_template("components/user_nav", [], true)
    engine_root = Gem.loaded_specs.fetch("studio-engine").full_gem_path
    assert template.identifier.start_with?(engine_root), "rendered from #{template.identifier}"
    assert_equal :player_name, Studio.navbar_user_name
  end

  private

  def ancestor_classes(node)
    [ node, *node.ancestors ].filter_map { |el| el["class"]&.split if el.respond_to?(:[]) }
  end

  def shown_on_phone?(node)
    ancestor_classes(node).none? { |classes| classes.include?("hidden") }
  end

  def shown_on_desktop?(node)
    ancestor_classes(node).none? do |classes|
      classes.include?("md:hidden") || (classes.include?("hidden") && (classes & %w[md:flex md:inline-flex md:block]).empty?)
    end
  end
end

# [component] The signed-out navbar says "Sign in", as every other Cyvasse
# page does (test/views/sign_in_wording_test.rb): the engine's button reads
# Studio.sign_in_label, which Cyvasse sets.
class NavbarSignedOutTest < ActionDispatch::IntegrationTest
  test "the signed-out navbar offers Sign in and never Log in" do
    assert_equal "Sign in", Studio.sign_in_label
    get root_path
    assert_response :success
    assert_select "header[data-pin=nav] a[href='#{login_path}']", text: "Sign in", minimum: 1
    assert_select "header[data-pin=nav] a", text: /\bLog ?in\b/, count: 0
    assert_select "header[data-pin=nav] [data-nav-name]", count: 0
  end
end
