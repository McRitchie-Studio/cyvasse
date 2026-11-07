require "test_helper"

# [integration] The friendly not-found page (task apps-adopt-not-found-page;
# studio-engine docs/NOT_FOUND_PAGE.md): a lost visitor gets a 404 with
# Cyvasse's name and a button home, never a 200 or a redirect.
# config.exceptions_app is guarded until the release relocks an engine that has
# Studio::ExceptionsApp, so these read whichever engine is locked: the engine
# page in the app's layout, or the branded public/404.html (same words, same
# data-test hooks). The test env hides exceptions, so each request runs with
# production's exception settings.
class NotFoundPageTest < ActionDispatch::IntegrationTest
  APP_NAME = "Cyvasse"
  ENGINE_PAGE = defined?(Studio::ExceptionsApp)
  OLD_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36"

  def with_production_exceptions
    config = Rails.application.env_config
    saved = config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    config["action_dispatch.show_exceptions"] = :all
    config["action_dispatch.show_detailed_exceptions"] = false
    yield
  ensure
    config.merge!(saved)
  end

  def get_lost(path, **options)
    with_production_exceptions { get path, **options }
  end

  # The page a lost visitor sees, on either engine: status 404, the friendly
  # words, the app's name and one button back to the app's root.
  def assert_friendly_page
    assert_response :not_found
    assert_nil response.location, "never a redirect"
    assert_match %r{\Atext/html}, response.media_type
    assert_select "[data-test='not-found']", count: 1 do
      assert_select "h1", text: "This page isn’t here"
      assert_select "a[data-test='not-found-home'][href='/']", text: "Back to #{APP_NAME}", count: 1
    end
    assert_select "title", "Page not found · #{APP_NAME}"
    if ENGINE_PAGE
      assert_select "[data-studio-not-found]", count: 1, message: "the engine's page, inside the layout"
      assert_select "[data-static-404]", count: 0
    else
      assert_select "body[data-static-404]", count: 1
    end
  end

  test "an unknown address answers 404 with the friendly page and a home link to the root" do
    get_lost "/no-such-page"

    assert_friendly_page
  end

  test "a deeper unknown address, signed out, gets the page, not a sign-in redirect" do
    get_lost "/no/such/page/either"

    assert_friendly_page
    assert_not response.redirect?
  end

  # allow_browser :modern answers an old browser with a 406. On the engine page
  # that answer is thrown away and the branded public/404.html answers; on the
  # locked engine Rails serves the same file. Status 404 either way.
  test "an old browser gets the branded static page, status 404" do
    get_lost "/no-such-page", headers: { "User-Agent" => OLD_BROWSER }

    assert_response :not_found
    assert_select "body[data-static-404] [data-test='not-found']", count: 1
    assert_select "a[data-test='not-found-home'][href='/']", text: "Back to #{APP_NAME}"
    assert_select "[data-studio-not-found]", count: 0
  end

  test "a JSON request answers 404 JSON, not the HTML page" do
    get_lost "/no-such-page", headers: { "Accept" => "application/json" }

    assert_response :not_found
    assert_equal "application/json", response.media_type
    assert_equal({ "status" => 404, "error" => "Not Found" }, response.parsed_body)
    assert_not_includes response.body, "<html"
  end

  test "a .json address answers 404 JSON" do
    get_lost "/no-such-page.json"

    assert_response :not_found
    assert_equal "application/json", response.media_type
    assert_not_includes response.body, "<html"
  end

  test "config/application.rb wires the engine's exceptions app once the engine has it" do
    if ENGINE_PAGE
      assert_kind_of Studio::ExceptionsApp, Rails.application.config.exceptions_app
    else
      assert_nil Rails.application.config.exceptions_app, "the guard keeps Rails' own until the relock"
    end
  end

  test "the static last resort, public/404.html, carries the brand, the words and the home link" do
    page = Nokogiri::HTML(Rails.public_path.join("404.html").read)

    assert_equal "Page not found · #{APP_NAME}", page.at_css("title").text
    assert page.at_css("body[data-static-404] [data-test='not-found']")
    assert_equal "This page isn’t here", page.at_css("h1").text
    home = page.at_css("a[data-test='not-found-home']")
    assert_equal "/", home["href"]
    assert_equal "Back to #{APP_NAME}", home.text
    assert page.at_css("img[src='/icon.png'][alt='Cyvasse']"), "the brand mark"
    assert Rails.public_path.join("icon.png").file?, "/icon.png is in public/"
assert_includes page.at_css("style").text, %(url("/cyvasse-404-background.jpg")), "the board art behind the card"
assert Rails.public_path.join("cyvasse-404-background.jpg").file?, "/cyvasse-404-background.jpg is in public/"
assert_operator Rails.public_path.join("cyvasse-404-background.jpg").size, :<, 150_000, "a small copy, not the full art"
    assert_includes page.at_css("style").text, "prefers-color-scheme: dark"
    assert_empty page.css("script"), "the last resort runs nothing"
    assert_empty page.css("link[rel='stylesheet']"), "and loads nothing that could be missing"
  end
end
