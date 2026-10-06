require "test_helper"

# [integration] The engine's survey primitive in Cyvasse (studio-engine
# docs/SURVEYS.md; task cyvasse-first-game-survey): the first-game survey is
# public, a response is credited to the email that brought the respondent the
# way EmailReferral credits everything else, completing it reports the hub's
# survey_completed goal for that email, and the results are admin-only.
class SurveysTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveResults

  REF = "AbCdEfGhIjKlMnOpQrSt12"
  SURVEY = "/surveys/first-game"

  def finish_survey(**params)
    post SURVEY, params: { answers: { overall: "4", found_us: "an_email_from_us" } }.merge(params)
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

  test "Cyvasse owns neither path itself: both come from the engine" do
    assert_equal "studio/surveys", Rails.application.routes.recognize_path(SURVEY)[:controller]
    assert_equal "studio/admin_surveys", Rails.application.routes.recognize_path("/admin/surveys")[:controller]
  end

  test "the first-game survey opens to anyone, with a ref that is not a token" do
    get "#{SURVEY}?ref=test"

    assert_response :success
    assert_select "[data-studio-survey]"
    assert_select "fieldset", 6
    assert_includes response.body, "How was your first game?"
    assert_nil cookies[:email_ref], "?ref=test is no delivery token, so nothing is remembered"
    # Engine 0.87 turned the footer on by default; Cyvasse declares its own, and
    # the layout's one studio_site_footer call still draws exactly one.
    assert_select "footer[data-site-footer]", 1
  end

  test "a response from an email link is stamped with its ref and reports survey_completed" do
    get "#{SURVEY}?ref=#{REF}"
    assert_response :success

    assert_enqueued_with(job: EmailGoalBeaconJob, args: [ REF, "survey_completed" ]) { finish_survey }

    response_row = Studio::SurveyResponse.sole
    assert response_row.completed?
    assert_equal REF, response_row.email_ref
    assert_equal 4, response_row.answers.dig("overall", "value").to_i
  end

  test "the ref the cookie remembers from an earlier page credits the response" do
    get "/play?ref=#{REF}"
    get SURVEY

    assert_enqueued_with(job: EmailGoalBeaconJob, args: [ REF, "survey_completed" ]) { finish_survey }
    assert_equal REF, Studio::SurveyResponse.sole.email_ref
  end

  test "an anonymous response no email brought is credited to no email" do
    get SURVEY

    assert_no_enqueued_jobs(only: EmailGoalBeaconJob) { finish_survey }
    response_row = Studio::SurveyResponse.sole
    assert response_row.completed?
    assert_nil response_row.email_ref
  end

  test "the completion beacon is the hub's goal URL for that email" do
    get "#{SURVEY}?ref=#{REF}"
    requested = []
    fake_http = Object.new
    fake_http.define_singleton_method(:get) { |path| requested << path; Net::HTTPOK.new("1.1", "200", "OK") }
    started = ->(host, port, **opts, &block) { requested << [ host, port, opts[:use_ssl] ]; block.call(fake_http) }

    with_stubbed(Net::HTTP, :start, started) { perform_enqueued_jobs(only: EmailGoalBeaconJob) { finish_survey } }

    assert_equal [ [ "localhost", 3000, false ], "/e/g/#{REF}?g=survey_completed" ], requested
  end

  test "the results are admin-only and list the first-game survey" do
    get "/admin/surveys"
    assert_redirected_to login_path

    log_in_as(player("arya"))
    get "/admin/surveys"
    assert_redirected_to root_path

    reset!
    log_in_as(player("warden", role: "admin"))
    get "/admin/surveys"
    assert_response :success
    assert_includes response.body, "first-game"
    get "/admin/surveys/first-game"
    assert_response :success
    assert_includes response.body, "How clear were the rules?"
  end
end
