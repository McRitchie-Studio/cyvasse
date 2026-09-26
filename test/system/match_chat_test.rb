require "application_system_test_case"

# [e2e] Send a message in a match's chat and see it in the other player's
# inbox, then answer it from there.
class MatchChatSystemTest < ApplicationSystemTestCase
  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne")
    @match = Match.challenge!(@arya, "brienne")
  end

  test "send a match message and see it in the inbox" do
    sign_in(@arya)
    visit match_path(@match)
    within("[data-controller=chat]") do
      assert_text "No messages yet. Say hello to brienne."
      fill_in "Message brienne", with: "Good luck, you will need it"
      click_on "Send"
      assert_selector ".chat-message.is-mine", text: "Good luck, you will need it"
      assert_field "Message brienne", with: "", wait: 2
    end

    using_session("brienne") do
      sign_in(@brienne)
      visit inbox_path
      within("[data-inbox]") do
        assert_selector ".unread-dot", text: "1"
        assert_text "Good luck, you will need it"
        click_on "arya"
      end
      assert_selector "[data-thread] .chat-message", text: "Good luck, you will need it"
      fill_in "Reply to arya", with: "We shall see"
      click_on "Send"
      assert_selector "[data-thread] .chat-message.is-mine", text: "We shall see"
    end

    assert_equal [ "Good luck, you will need it", "We shall see" ], Message.chronological.pluck(:message)
    assert Message.find_by(sender: @arya).read, "Brienne opened it"
  end

  private

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end
end
