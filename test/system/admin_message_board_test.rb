require "application_system_test_case"

# [e2e] An admin opens the Message Board from the Conversations page and
# reads the old public board, newest first, at phone width with no sideways
# scroll; blank posts are not shown. A player who types the URL gets a 404.
class AdminMessageBoardSystemTest < ApplicationSystemTestCase
  setup do
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin")
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne-has-a-rather-long-address@example.com", name: "Brienne", username: "brienne")
    BoardPost.create!(user: @arya, message: "anyone for a game tonight?", created_at: Time.utc(2015, 2, 1, 20))
    BoardPost.create!(user: @brienne, message: "rematch next week", created_at: Time.utc(2016, 5, 3, 9))
    BoardPost.create!(user: @brienne, message: "   ", created_at: Time.utc(2017, 1, 1))
  end

  test "an admin reads the board, newest first, at phone width" do
    page.driver.browser.manage.window.resize_to(375, 900)
    sign_in(@admin)
    visit admin_conversations_path
    click_on "Message Board"

    assert_selector "h1", text: "Message Board"
    assert_equal [ "rematch next week", "anyone for a game tonight?" ], all("[data-board-post] .chat-text").map(&:text)
    assert_equal %w[brienne arya], all("[data-author]").map(&:text)
    assert_text "1 blank post kept but not shown."
    widths = page.evaluate_script("[document.documentElement.scrollWidth, document.documentElement.clientWidth]")
    assert_operator widths.first, :<=, widths.last, "no sideways scroll at phone width"
  end

  test "a player who types the URL sees nothing of the board" do
    sign_in(@arya)
    visit admin_message_board_path
    assert_no_text "anyone for a game tonight?"
    assert_no_selector "[data-board-posts]"
  end

  private

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end
end
