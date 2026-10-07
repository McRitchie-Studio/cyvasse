require "test_helper"
require "csv"

# [integration] The play-times survey over HTTP (task cyvasse-play-times-survey):
# it opens to an email link's ref, a legacy player can skip the first-game
# question, completing it reports the hub's survey_completed goal for that email
# through the same slug-agnostic hooks as first-game, and its results are
# admin-only.
class PlayTimesSurveyFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveResults

  REF = "PlayTimesRef0123456789"
  SURVEY = "/surveys/play-times"
  ANSWERS = { times: %w[evening late_night], days: %w[friday saturday], time_zone: "mountain" }.freeze

  def finish_survey(answers = ANSWERS)
    post SURVEY, params: { answers: answers }
    assert_redirected_to "#{SURVEY}/thanks"
  end

  # Minitest 6 has no stub; swap the singleton method in and always put it back.
  def with_stubbed(klass, name, replacement)
    original = klass.method(name)
    klass.define_singleton_method(name, &replacement)
    yield
  ensure
    klass.singleton_class.send(:remove_method, name)
    klass.define_singleton_method(name, original) unless klass.respond_to?(name)
  end

  test "an email link with a delivery token opens the six-question survey" do
    get "#{SURVEY}?ref=#{REF}"

    assert_response :success
    assert_select "[data-studio-survey]"
    assert_select "fieldset", 6
    assert_includes response.body, "Cyvasse Night: tell us about you"
    assert_includes response.body, "How was your game on the new Cyvasse?"
    assert_includes response.body, "Haven&#39;t played yet? Skip this one."
    assert_equal REF, cookies[:email_ref], "the ref is remembered like any other email arrival"
  end

  test "a legacy player skips the first-game question; the response is credited and reports survey_completed" do
    get "#{SURVEY}?ref=#{REF}"

    assert_enqueued_with(job: EmailGoalBeaconJob, args: [ REF, "survey_completed" ]) { finish_survey }

    row = Studio::SurveyResponse.sole
    assert_equal "play-times", row.survey_slug
    assert row.completed?
    assert_equal REF, row.email_ref
    assert_nil row.answers["first_game"]
    assert_equal %w[evening late_night], row.answers.dig("times", "value")
    assert_equal "mountain", row.answers.dig("time_zone", "value")
  end

  test "completing it requests the hub's goal URL for that email (Net::HTTP stubbed)" do
    get "#{SURVEY}?ref=#{REF}"
    requested = []
    fake_http = Object.new
    fake_http.define_singleton_method(:get) { |path| requested << path; Net::HTTPOK.new("1.1", "200", "OK") }
    started = ->(host, port, **opts, &block) { requested << [ host, port, opts[:use_ssl] ]; block.call(fake_http) }

    with_stubbed(Net::HTTP, :start, started) { perform_enqueued_jobs(only: EmailGoalBeaconJob) { finish_survey } }

    assert_equal [ [ "localhost", 3000, false ], "/e/g/#{REF}?g=survey_completed" ], requested
  end

  test "the time zone is required: without it nothing completes and nothing is reported" do
    get "#{SURVEY}?ref=#{REF}"

    assert_no_enqueued_jobs(only: EmailGoalBeaconJob) do
      post SURVEY, params: { answers: ANSWERS.except(:time_zone) }
    end
    assert_not Studio::SurveyResponse.where(survey_slug: "play-times").completed.exists?
  end

  test "the results are admin-only and break play-times down by question" do
    get "#{SURVEY}?ref=#{REF}"
    finish_survey(ANSWERS.merge(first_game: "5", how_often: "every_other_week"))

    get "/admin/surveys/play-times"
    assert_redirected_to login_path

    log_in_as(player("warden", role: "admin"))
    get "/admin/surveys"
    assert_response :success
    assert_includes response.body, "play-times"
    get "/admin/surveys/play-times"
    assert_response :success
    assert_includes response.body, "Which time zone are you in?"
    assert_includes response.body, "Every other week"
    assert_includes response.body, "🌆 Evening", "the admin breakdown shows the emoji label"

    get "/admin/surveys/play-times/export"
    assert_response :success
    row = CSV.parse(response.body.force_encoding("UTF-8"), headers: true).first
    assert_equal REF, row["email_ref"]
    # The CSV carries option values, and [value, label] keeps the emoji out of them.
    assert_equal "evening; late_night", row["times"]
  end
end
