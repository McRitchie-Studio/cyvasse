require "test_helper"

# [unit] config/surveys/play_times.rb, the second definition the engine loads at
# boot (task cyvasse-play-times-survey): a skippable first-game question for
# players new and old, then when they are free for a standing Cyvasse Night.
class PlayTimesSurveyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Rails.application.routes.url_helpers

  REF = "AbCdEfGhIjKlMnOpQrSt12"

  def survey = Studio.survey("play-times")

  test "the survey asks six questions in order, anonymous answers allowed" do
    assert survey, "config/surveys/play_times.rb is loaded"
    assert_equal %w[first_game times days time_zone how_often anything_else], survey.keys
    assert_equal %w[emoji_scale multi_choice multi_choice choice choice long_text],
                 survey.questions.map { |q| q.type.to_s }
    assert survey.allow_anonymous?
    assert_not_equal Studio.survey("first-game").version, survey.version
    assert_not survey.title_repeats_first_question?, "the h1 and question 1 ask different things, so both paint"
  end

  test "the first-game question is the first survey's scale, and a player who has not played can skip it" do
    question = survey.question("first_game")
    overall = Studio.survey("first-game").question("overall")

    assert_equal "How was your game on the new Cyvasse?", question.label
    assert_equal overall.type, question.type
    assert_equal overall.options.map(&:to_h), question.options.map(&:to_h)
    assert_not question.required?
    assert_equal "Haven't played yet? Skip this one.", question.help
  end

  test "times, days and time zone are required; how often and anything else are not" do
    assert_equal({ "first_game" => false, "times" => true, "days" => true, "time_zone" => true,
                   "how_often" => false, "anything_else" => false },
                 survey.questions.to_h { |q| [ q.key.to_s, q.required? ] })
  end

  test "the options read in order, and both multi-selects say to pick all that apply" do
    assert_equal [ "🌅 Morning", "☀️ Afternoon", "🌆 Evening", "🌙 Late night" ], survey.question("times").options.map(&:label)
    assert_equal %w[morning afternoon evening late_night], survey.question("times").options.map(&:value)
    assert_equal %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday], survey.question("days").options.map(&:label)
    assert_equal [ "Pacific", "Mountain", "Central", "Eastern", "UK / Europe", "Somewhere else" ],
                 survey.question("time_zone").options.map(&:label)
    assert_equal [ "Every week", "Every other week", "Once a month", "Just tell me when" ],
                 survey.question("how_often").options.map(&:label)
    assert_equal [ "Pick all that apply." ] * 2, [ survey.question("times").help, survey.question("days").help ]
  end

  test "its next action is a game now, on the real play page" do
    assert_equal({ label: "Play a game now", url: play_path }, survey.next_action.to_h.slice(:label, :url))
  end

  test "the completion hook is not first-game's alone: a play-times response reports its ref" do
    response = Studio::SurveyResponse.new(survey_slug: "play-times", email_ref: REF)

    assert_enqueued_with(job: EmailGoalBeaconJob, args: [ REF, "survey_completed" ]) do
      Studio.on_survey_completed.call(response)
    end
  end
end
