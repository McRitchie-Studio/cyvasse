require "test_helper"

# [unit] User#can_message?, the one rule for who may message whom (task
# cyvasse-live-chat), and the counts built on it: people once they have shared
# a match (any status, legacy included), never yourself, never a stranger,
# and a computer player only inside a match the two of them share.
class UserCanMessageTest < ActiveSupport::TestCase
  include MatchPlay

  setup do
    @arya, @brienne, @cersei = %w[arya brienne cersei].map { make_player(_1) }
    @tyrion = User.seed_computer_player!("tyrion")
  end

  test "two people who shared a match may message each other, either way" do
    Match.challenge!(@arya, "brienne")
    assert @arya.can_message?(@brienne)
    assert @brienne.can_message?(@arya)
  end

  test "people who never played may not" do
    Match.challenge!(@arya, "brienne")
    assert_not @arya.can_message?(@cersei)
    assert_not @cersei.can_message?(@brienne)
  end

  test "any match counts, in any status, a legacy imported one included" do
    Match.create!(home_user: @cersei, away_user: @arya, match_status: Match::FINISHED, legacy_id: 4242)
    assert @arya.can_message?(@cersei)

    declined = Match.challenge!(@brienne, "cersei")
    declined.update!(match_status: Match::FINISHED)
    assert @cersei.can_message?(@brienne)
  end

  test "nobody may message themselves, or nobody" do
    Match.challenge!(@arya, "brienne")
    assert_not @arya.can_message?(@arya)
    assert_not @arya.can_message?(nil)
  end

  test "a computer player: only inside a match the two of them are playing" do
    match = Match.create!(home_user: @arya, away_user: @tyrion, match_status: Match::IN_PROGRESS)

    assert_not @arya.can_message?(@tyrion), "not from the Chat hub, even after a game"
    assert_not @tyrion.can_message?(@arya)
    assert @arya.can_message?(@tyrion, match:)
    assert @tyrion.can_message?(@arya, match:)

    theirs = Match.challenge!(@brienne, "cersei")
    assert_not @arya.can_message?(@tyrion, match: theirs), "only a match both are in"
  end

  test "the rule is checked on every new message; legacy rows are imported as they were" do
    refused = Message.new(sender: @arya, receiver: @cersei, message: "hi")
    assert_not refused.valid?
    assert_includes refused.errors[:base], Message::NOT_ALLOWED
    assert_raises(ActiveRecord::RecordInvalid) { Message.send_direct!(@arya, @cersei, "hi") }

    assert Message.new(sender: @arya, receiver: @cersei, message: "hi", legacy_id: 77).valid?
  end

  test "played_humans lists people played, newest match first, never a computer or yourself" do
    Match.challenge!(@arya, "cersei")
    Match.create!(home_user: @arya, away_user: @tyrion, match_status: Match::FINISHED)
    Match.challenge!(@brienne, "arya")

    assert_equal [ @brienne, @cersei ], @arya.played_humans
    assert_empty @tyrion.played_humans.select(&:computer?)
  end

  test "the unread count is messages from people alone" do
    human = Match.challenge!(@brienne, "arya")
    bot = Match.create!(home_user: @arya, away_user: @tyrion, match_status: Match::IN_PROGRESS)
    Message.post_in_match!(human, @brienne, "your move")
    Message.post_in_match!(bot, @tyrion, "Luck is for dice.")

    assert_equal 1, @arya.unread_messages_count
    assert_equal [ @tyrion ], User.computers.where(id: [ @tyrion.id, @arya.id ]).to_a
    assert_equal [ @arya ], User.humans.where(id: [ @tyrion.id, @arya.id ]).to_a
  end
end
