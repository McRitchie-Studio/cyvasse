require "test_helper"

# [component] The two match emails: who they go to, what they say, where the
# link lands, and the sender the app is configured with.
class MatchMailerTest < ActionMailer::TestCase
  include MatchPlay

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  test "a challenge names the challenger and links to the match" do
    match = Match.challenge!(@home, "brienne")
    mail = MatchMailer.challenged(match, @away)

    assert_equal [ "brienne@example.com" ], mail.to
    assert_equal "arya challenges you to Cyvasse", mail.subject
    assert_includes mail.text_part.body.to_s, "http://example.com/matches/#{match.id}"
    assert_includes mail.html_part.body.to_s, "seven days"
  end

  test "your turn says who moved, links to the match, and gives the deadline" do
    match = started_match(@home, @away)
    match.play!(@home, steps_for(GAME.fetch("turns").first))
    mail = MatchMailer.your_turn(match.reload, @away)

    assert_equal [ "brienne@example.com" ], mail.to
    assert_equal "Your move against arya · Cyvasse", mail.subject
    body = mail.text_part.body.to_s
    assert_includes body, "arya has moved"
    assert_includes body, "/matches/#{match.id}"
    assert_includes body, match.deadline.utc.strftime("%B %-d")
    assert_includes body, "forfeit"
  end

  test "the first move of a game is announced as such" do
    match = started_match(@home, @away)
    assert_includes MatchMailer.your_turn(match.reload, @home).text_part.body.to_s, "you have the first move"
  end

  test "mail comes from the configured sender, not the scaffold placeholder" do
    match = Match.challenge!(@home, "brienne")
    from = MatchMailer.challenged(match, @away).from
    assert_not_includes from, "from@example.com"
    assert_equal Mail::Address.new(Studio.mailer_from).address, from.first if Studio.mailer_from
  end

  test "the queued delivery renders from its outbox row" do
    match = Match.challenge!(@home, "brienne")
    delivery = Studio::EmailDelivery.find_by!(email_key: "MatchMailer#challenged")
    args = ActiveJob::Arguments.deserialize(delivery.args)

    assert_equal [ match, @away ], args
    assert_equal "arya challenges you to Cyvasse", MatchMailer.public_send(delivery.action, *args).subject
  end
end
