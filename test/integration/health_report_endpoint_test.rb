require "test_helper"

# [integration] GET /_studio/health_report, the endpoint studio-engine 0.109.0
# draws and the McRitchie Studio hub pulls every morning at 07:00
# America/Denver (its DailyAppReport and Tyrion's CTO report) with
# HEALTH_TOKEN_CYVASSE as the bearer. Production holds the same value as
# STUDIO_HEALTH_TOKEN (Heroku `cyvasse`), so these tests set the env var, not
# Studio.health_report_token: that is how the app is actually configured.
#
# Through Cyvasse's own router and middleware stack, so a host-side catch-all,
# before_action or the canonical-host redirect would show here.
class HealthReportEndpointTest < ActionDispatch::IntegrationTest
  TOKEN = "cyvasse-hub-pull-token-0123456789".freeze
  PATH = "/_studio/health_report".freeze

  setup do
    @previous_token = ENV["STUDIO_HEALTH_TOKEN"]
    @previous_host = ENV["CANONICAL_HOST"]
    ENV["STUDIO_HEALTH_TOKEN"] = TOKEN
  end

  teardown do
    ENV["STUDIO_HEALTH_TOKEN"] = @previous_token
    ENV["CANONICAL_HOST"] = @previous_host
  end

  test "with no token configured the endpoint answers a bare 404" do
    ENV.delete("STUDIO_HEALTH_TOKEN")

    get PATH, headers: { "Authorization" => "Bearer #{TOKEN}" }

    assert_response :not_found
    assert_empty response.body
  end

  test "without the bearer it answers 401 JSON" do
    get PATH

    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, response.parsed_body)
  end

  test "a wrong bearer answers 401" do
    get PATH, headers: { "Authorization" => "Bearer not-the-token" }

    assert_response :unauthorized
  end

  test "with the bearer it answers 200 JSON: Cyvasse's counts, signups from User" do
    User.create!(email: "new-player@example.com", name: "New Player", created_at: 2.hours.ago)
    ending = Time.current.iso8601

    get PATH, params: { ending: ending }, headers: { "Authorization" => "Bearer #{TOKEN}", "Accept" => "application/json" }

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    assert_equal "Cyvasse", body["app"]
    assert_equal Studio::VERSION, body["engine_version"]

    sections = body["sections"].index_by { |section| section["key"] }
    assert_equal %w[errors signups], sections.keys.sort, "Cyvasse has no contact model, so no contacts section"
    assert_nil sections["signups"]["failure"]
    assert_operator sections["signups"]["count"], :>=, 1
    refute_includes response.body, "new-player@example.com", "counts only: no signup's email leaves the app"
  end

  # The hub fetches https://cyvasse.xyz, but an operator's curl against the
  # herokuapp or old host sends Accept: */*, which the canonical-host redirect
  # reads as a navigation. A 301 there would drop the Authorization header on
  # the cross-host hop, the same reason /api/ is exempt.
  test "the canonical-host redirect never bounces the endpoint" do
    ENV["CANONICAL_HOST"] = "cyvasse.xyz"
    host! "cyvasse.mcritchie.studio"

    get PATH, headers: { "Authorization" => "Bearer #{TOKEN}", "Accept" => "*/*" }

    assert_response :success
  end
end
