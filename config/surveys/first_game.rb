# The first-game survey (studio-engine docs/SURVEYS.md): /surveys/first-game.
# Results at /admin/surveys. Sending the link is not the engine's job; an email
# that carries ?ref=<delivery token> credits the answer to that email, and
# completing it reports survey_completed to the hub (config/initializers/studio.rb).
Studio.define_survey "first-game" do
  title "How was your first game?"
  intro "Six quick questions. Your answers shape what we build next."
  thank_you "We read every answer."
  next_action label: "Play another game", url: "/play"
  allow_anonymous true

  emoji_scale  :overall, "How was your first game?", required: true
  rating       :rules, "How clear were the rules?", low_label: "Very confusing", high_label: "Crystal clear"
  choice       :found_us, "How did you find us?",
               options: [ "An email from us", "A friend", "Search", "Somewhere else" ]
  multi_choice :liked, "What did you enjoy?",
               options: [ "The board", "The pace", "The art", "Playing a friend", "Playing the computer" ]
  short_text   :one_word, "Describe it in one word."
  long_text    :anything_else, "Anything else we should know?", help: "Bugs, ideas — all welcome."
end
