# The play-times survey (studio-engine docs/SURVEYS.md): /surveys/play-times.
# Feedback from players new and old on the new Cyvasse, then when they are free,
# so a standing, biweekly Cyvasse Night lands when the most people can play
# live. Results at /admin/surveys. Like first_game.rb, an email that carries
# ?ref=<delivery token> credits the answer to that email, and completing it
# reports survey_completed to the hub: both hooks in config/initializers/studio.rb
# apply to every survey, whatever its slug.
Studio.define_survey "play-times" do
  title "Cyvasse Night: tell us about you"
  intro "Tell us how the new Cyvasse is going, and help us pick a regular Cyvasse Night when the most people can play live."
  thank_you "Thanks! We'll share the Cyvasse Night time soon."
  next_action label: "Play a game now", url: "/play"
  allow_anonymous true

  # Not required: many recipients are legacy players who have not tried the new
  # version yet, and they must be able to skip straight past it.
  emoji_scale  :first_game, "How was your first game on the new Cyvasse?",
               help: "Haven't played yet? Skip this one."
  multi_choice :times, "What time of day are you usually free to play?", required: true,
               help: "Pick all that apply.",
               options: [ "Morning", "Afternoon", "Evening", "Late night" ]
  multi_choice :days, "Which days work best?", required: true,
               help: "Pick all that apply.",
               options: %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday]
  choice       :time_zone, "Which time zone are you in?", required: true,
               options: [ "Pacific", "Mountain", "Central", "Eastern", "UK / Europe", "Somewhere else" ]
  choice       :how_often, "How often would you join a Cyvasse Night?",
               options: [ "Every week", "Every other week", "Once a month", "Just tell me when" ]
  long_text    :anything_else, "Anything that would make you more likely to show up?"
end
