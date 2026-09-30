require "test_helper"

# [component] UX audit #2 (#13): the hero and the game-over modal say "Sign in"
# and the navbar said "Log in". Every view and script Cyvasse renders says
# "Sign in", and so does the engine's navbar since studio-engine 0.80.0 took
# the label as config (Studio.sign_in_label; task
# cyvasse-navbar-config-switch). The engine's /login page (sessions/new) is
# still the engine's own wording, with no setting, and is not visited here.
class SignInWordingTest < ActionDispatch::IntegrationTest
  LOG_IN = /\bLog ?in\b/

  test "no Cyvasse view or script says Log in" do
    files = Dir[Rails.root.join("app/views/**/*.erb"), Rails.root.join("app/javascript/**/*.js"),
                Rails.root.join("app/helpers/**/*.rb"), Rails.root.join("app/models/**/*.rb")]
    assert_operator files.size, :>, 50, "the scan found the app's files"
    offenders = files.select { |file| File.read(file).match?(LOG_IN) }
    assert_empty offenders.map { _1.delete_prefix("#{Rails.root}/") }
  end

  test "the pages a guest sees say Sign in, the navbar included" do
    %w[/ /rules /play /leaderboard /pieces /about].each do |path|
      get path
      assert_response :success, path
      doc = Nokogiri::HTML5(response.body)
      doc.css("script, style").each(&:remove)
      assert_no_match LOG_IN, doc.text, path
      assert_match(/Sign in/, doc.css("header[data-pin=nav]").text, "#{path}: the navbar's button")
    end
    get "/"
    assert_match(/Sign in/, response.body, "the front door offers Sign in")
  end
end
