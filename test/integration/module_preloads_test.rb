require "test_helper"

# [integration] What each page preloads (config/importmap.rb page groups,
# ApplicationHelper#preload_modules), the page's html lang, and the home
# hero's fetch priority. Controllers load lazily (controllers/index.js), so
# the load itself is proven in the browser by the system tests that play a
# game; this holds the preloads that keep that load from waterfalling.
class ModulePreloadsTest < ActionDispatch::IntegrationTest
  include MatchPlay

  BOARD_MODULES = %w[controllers/cyvasse_game_controller controllers/cyvasse_match_controller
                     controllers/chat_controller cyvasse/game cyvasse/ai cyvasse/board].freeze

  # Every modulepreload href on the page, as its pin name ("cyvasse/game").
  def preloaded
    css_select("link[rel=modulepreload]").map { |link| pin_for(link["href"]) }
  end

  def pin_for(href)
    @pins_by_path ||= Rails.application.importmap.send(:expanded_packages_and_directories).values
                           .index_by { |package| ActionController::Base.helpers.asset_path(package.path) }
    @pins_by_path.fetch(href) { flunk "modulepreload of #{href}, which is not a pin" }.name
  end

  def mounted_controllers
    css_select("[data-controller]").flat_map { |node| node["data-controller"].split }.uniq
  end

  def assert_preloads_what_it_mounts
    missing = mounted_controllers.map { |name| "controllers/#{name.tr("-", "_")}_controller" } - preloaded
    assert_empty missing, "the page mounts these controllers but does not preload them"
  end

  def assert_preloads_after_the_import_map
    html = response.body
    importmap_at = html.index('<script type="importmap"')
    assert importmap_at, "no import map on the page"
    first_preload_at = html.index('rel="modulepreload"')
    assert_operator first_preload_at, :>, importmap_at, "a modulepreload before the import map makes the browser ignore the map"
  end

  test "the front door declares its language" do
    get root_path

    assert_select "html[lang=en]"
  end

  test "the front door preloads the modules every page runs and its gallery, and none of the game" do
    get root_path

    assert_includes preloaded, "application"
    assert_includes preloaded, "controllers"
    assert_includes preloaded, "controllers/home_gallery_controller"
    assert_empty preloaded & BOARD_MODULES
    assert_empty preloaded.grep(%r{\Acyvasse/}) - [ "cyvasse/sign_in" ], "the game engine is preloaded on the front door"
    assert_preloads_what_it_mounts
    assert_preloads_after_the_import_map
  end

  test "the hero's first slide is fetched at high priority, and it alone" do
    get root_path

    assert_select ".home-slide:first-child img[fetchpriority=high][loading=eager][src]", 1
    assert_select "img[fetchpriority=high]", 1
    assert_select "link[rel=preload][as=image][fetchpriority=high]", 2
  end

  test "the computer game preloads the board it mounts" do
    get play_path

    assert_select "html[lang=en]"
    assert_includes preloaded, "controllers/cyvasse_game_controller"
    assert_includes preloaded, "cyvasse/game"
    assert_includes preloaded, "cyvasse/smart_setup"
    assert_preloads_what_it_mounts
    assert_preloads_after_the_import_map
  end

  test "a match preloads the board and the chat it mounts" do
    home = make_player("arya")
    log_in_as(home)
    get match_path(started_match(home, make_player("brienne")))

    assert_includes mounted_controllers, "chat"
    assert_includes preloaded, "controllers/cyvasse_match_controller"
    assert_preloads_what_it_mounts
  end

  test "the searching page preloads its splash, not the board" do
    post live_seeks_path
    get live_seek_path(LiveSeek.last)

    assert_includes preloaded, "cyvasse/seek_splash"
    assert_empty preloaded & BOARD_MODULES
    assert_preloads_what_it_mounts
  end

  test "every module under the pinned directories is pinned, as pin_all_from would" do
    pins = Rails.application.importmap.send(:expanded_packages_and_directories)
    { "controllers" => "app/javascript/controllers", "cyvasse" => "app/javascript/cyvasse" }.each do |under, dir|
      Dir.glob("**/*.js", base: Rails.root.join(dir)).each do |file|
        path = "#{under}/#{file}"
        assert pins.values.any? { |package| package.path == path }, "#{path} is not pinned; restart after adding a module"
      end
    end
    assert_equal "controllers/index.js", pins.fetch("controllers").path
  end
end
