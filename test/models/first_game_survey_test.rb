require "test_helper"

# [unit] config/surveys/first_game.rb, the definition the engine loads at boot,
# and EmailReferral's two survey hooks (task cyvasse-first-game-survey).
class FirstGameSurveyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Rails.application.routes.url_helpers

  REF = "AbCdEfGhIjKlMnOpQrSt12"

  # A controller as the engine hands one to Studio.survey_ref_resolver.
  FakeController = Struct.new(:params, :email_ref) do
    private :email_ref
  end

  def controller(param: nil, cookie: nil)
    FakeController.new(ActionController::Parameters.new(ref: param), cookie)
  end

  test "the survey asks the six first-game questions, anonymous answers allowed" do
    survey = Studio.survey("first-game")

    assert survey, "config/surveys/first_game.rb is loaded"
    assert_equal %w[overall rules found_us liked one_word anything_else], survey.keys
    assert survey.allow_anonymous?
    assert survey.question("overall").required?
    assert_equal [ "Very confusing", "Crystal clear" ], [ survey.question("rules").low_label, survey.question("rules").high_label ]
    assert_equal [ "An email from us", "A friend", "Search", "Somewhere else" ],
                 survey.question("found_us").options.map(&:label)
    assert_equal 5, survey.question("liked").options.size
    assert_equal "Bugs, ideas — all welcome.", survey.question("anything_else").help
  end

  test "its next action is another game on the real play page" do
    assert_equal({ label: "Play another game", url: play_path }, Studio.survey("first-game").next_action.to_h.slice(:label, :url))
  end

  test "the ref resolver reads ?ref= first, then the remembered cookie" do
    assert_equal REF, EmailReferral.ref_for(controller(param: REF, cookie: "OtherRefOtherRef0001"))
    assert_equal REF, EmailReferral.ref_for(controller(cookie: REF))
    assert_equal REF, EmailReferral.ref_for(controller(param: "test", cookie: REF))
    assert_nil EmailReferral.ref_for(controller(param: "test"))
  end

  test "the engine's hooks are Cyvasse's" do
    assert_equal REF, Studio.survey_ref_resolver.call(controller(param: REF))

    response = Studio::SurveyResponse.new(email_ref: REF)
    assert_enqueued_with(job: EmailGoalBeaconJob, args: [ REF, "survey_completed" ]) do
      Studio.on_survey_completed.call(response)
    end
  end

  test "a goal is reported only for a delivery token" do
    assert_no_enqueued_jobs { EmailReferral.report_goal(nil, "survey_completed") }
    assert_no_enqueued_jobs { EmailReferral.report_goal("test", "survey_completed") }
  end
end
