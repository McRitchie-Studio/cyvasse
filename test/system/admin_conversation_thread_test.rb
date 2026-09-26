require "application_system_test_case"

# [e2e] An admin opens a conversation from the Conversations page and reads
# it grouped by game, the first-named player's bubbles on the left and the
# second's on the right, on a phone-width screen with no sideways scroll.
class AdminConversationThreadSystemTest < ApplicationSystemTestCase
  setup do
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin")
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne")
    @old = Match.create!(home_user: @arya, away_user: @brienne, match_status: Match::FINISHED,
                         winner: @brienne, finish_reason: "resigned", turn: 12)
    @new = Match.create!(home_user: @brienne, away_user: @arya, match_status: Match::FINISHED,
                         winner: @arya, finish_reason: "king", turn: 30)
    say(@arya, @brienne, "first game, first word", 3.days.ago, @old)
    say(@brienne, @arya, "first game, reply", 3.days.ago + 5.minutes, @old)
    say(@brienne, @arya, "between games", 2.days.ago, nil)
    say(@arya, @brienne, "second game opener", 1.day.ago, @new)
    say(@brienne, @arya, "second game reply", 1.day.ago + 5.minutes, @new)
  end

  test "an admin reads a conversation grouped by game with left and right bubbles" do
    page.driver.browser.manage.window.resize_to(390, 900)
    sign_in(@admin)
    visit admin_conversations_path
    click_on "5 messages"

    assert_selector "[data-game]", count: 3
    assert_equal [ @new.id.to_s, "none", @old.id.to_s ], all("[data-game]").map { _1["data-game"] }
    within("[data-game='#{@new.id}']") do
      assert_text "finished (king) · won by arya"
      assert_equal [ "second game opener", "second game reply" ], all(".chat-text").map(&:text)
      left, right = all(".chat-message").map { _1.rect }
      assert_operator right.x, :>, left.x, "brienne's bubble sits right of arya's"
      assert_operator (right.x + right.width).round, :>=, (left.x + left.width).round
    end
    assert_selector "[data-game=none] h2", text: "Outside any game"
    widths = page.evaluate_script("[document.documentElement.scrollWidth, document.documentElement.clientWidth]")
    assert_operator widths.first, :<=, widths.last, "no sideways scroll at phone width"

    click_on "Match ##{@old.id}"
    assert_current_path admin_match_path(@old)
  end

  private

  def say(from, to, text, at, match)
    Message.create!(sender: from, receiver: to, message: text, match: match, created_at: at, updated_at: at)
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end
end
