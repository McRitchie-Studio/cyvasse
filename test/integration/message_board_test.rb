require "test_helper"

# [integration] The admin Message Board (piece 15) and blank messages through
# the controllers. The board is admins' alone: a player gets a 404 and a
# signed-out visitor is sent to sign in, and no player-facing page shows a
# board post. Blank messages (empty or whitespace text, kept in the table)
# are hidden from the match chat, the inbox, the unread count and every
# admin page.
class MessageBoardTest < ActionDispatch::IntegrationTest
  include MatchPlay

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin", username: "boss")
    @match = Match.challenge!(@arya, "brienne")
    @secret = "board-#{SecureRandom.hex(4)}"
    @post = BoardPost.create!(user: @arya, message: @secret, created_at: Time.utc(2015, 3, 1, 9, 30))
  end

  # ---- The admin Message Board -----------------------------------------------

  test "a non-admin gets 404 on the admin message board" do
    log_in_as(@arya)
    get admin_message_board_path
    assert_response :not_found
    assert_not_includes response.body, @secret
    get admin_message_board_path(page: 2)
    assert_response :not_found
  end

  test "a signed-out visitor is sent to sign in from the message board" do
    get admin_message_board_path
    assert_response :redirect
    assert_no_match %r{/admin}, response.location
  end

  test "an admin reads every post with text, newest first, a page at a time; blank ones are counted, not shown" do
    newer = BoardPost.create!(user: @brienne, message: "newer post", created_at: Time.utc(2016, 1, 1))
    blank = BoardPost.create!(user: @brienne, message: " \n\t", created_at: Time.utc(2017, 1, 1))
    log_in_as(@admin)

    get admin_message_board_path
    assert_response :success
    assert_equal [ newer, @post ].map { _1.id.to_s }, css_select("[data-board-posts] li").map { _1["data-board-post"] }
    assert_select "[data-board-post=?]", blank.id.to_s, 0
    assert_select "[data-total]", /2 posts, newest first/
    assert_select "[data-blank]", /1 blank post kept but not shown/
    assert_select "[data-board-post=?] [data-author]", @post.id.to_s, "arya"
    assert_select "a[href=?]", admin_conversations_path

    BoardPost.where.not(id: blank.id).delete_all
    51.times { |i| BoardPost.create!(user: @arya, message: "post #{i}", created_at: Time.utc(2015, 1, 1) + i.days) }
    get admin_message_board_path
    assert_select "[data-board-posts] li", 50
    assert_select "a[rel=next][href=?]", admin_message_board_path(page: 2)
    get admin_message_board_path(page: 2)
    assert_select "[data-board-posts] li", 1
    assert_select "[data-board-posts] li", /post 0/
  end

  test "the admin nav and the Conversations page link the board for admins only" do
    log_in_as(@admin)
    get admin_conversations_path
    assert_select "a[data-board-link][href=?]", admin_message_board_path
    assert_select "a[href='/admin/message_board']"

    log_in_as(@arya)
    get root_path
    assert_select "a[href='/admin/message_board']", 0
  end

  test "no player-facing page shows a board post" do
    Message.post_in_match!(@match, @brienne, "hello arya")
    log_in_as(@arya)
    [ root_path, matches_path, match_path(@match), match_messages_path(@match), inbox_path,
      conversation_path(@brienne.id), play_path, rules_path, about_path, pieces_path ].each do |path|
      get path
      assert_response :success, path
      assert_not_includes response.body, @secret, "#{path} must not show a board post"
    end
  end

  # ---- Blank messages are hidden ---------------------------------------------

  test "blank messages are hidden in the chat, the inbox, the unread count and the admin pages" do
    Message.post_in_match!(@match, @brienne, "real words")
    blank_in_match = legacy_blank(@brienne, @arya, "   ", match: @match)
    legacy_blank(@brienne, @arya, "", match: nil)
    legacy_blank(@brienne, @arya, nil, match: nil).update_columns(created_at: 1.minute.from_now)

    log_in_as(@arya)
    assert_equal 1, @arya.unread_messages_count, "only the message with words counts"

    # The inbox first: reading the chat marks its messages read.
    get inbox_path
    assert_select "[data-conversation=?]", @brienne.id.to_s, /1 message/
    assert_select "[data-conversation=?] .unread-dot", @brienne.id.to_s, "1"
    assert_select "[data-conversation=?]", @brienne.id.to_s, /real words/, "the preview is the newest message with words"

    get match_messages_path(@match)
    assert_select ".chat-message", 1
    assert_select "[data-message-id=?]", blank_in_match.id.to_s, 0

    get conversation_path(@brienne.id)
    assert_select ".chat-message", 1

    log_in_as(@admin)
    key = [ @arya.id, @brienne.id ].minmax.join("-")
    get admin_conversations_path
    assert_select "[data-conversation=?]", key, /1 message/
    assert_select "[data-conversation=?]", key, /real words/
    get admin_conversation_path(key)
    assert_select ".chat-message", 1
    get admin_conversation_path(key, game: "none")
    assert_response :not_found, "the only messages outside a game are blank"
    get admin_match_path(@match)
    assert_select ".chat-message", 1
    assert_select "h2", /Chat \(1\)/
  end

  test "a conversation of blank messages alone is not listed and is a 404" do
    legacy_blank(@brienne, @arya, " ", match: nil)
    log_in_as(@arya)
    get inbox_path
    assert_select "[data-conversation]", 0
    get conversation_path(@brienne.id)
    assert_response :not_found

    log_in_as(@admin)
    get admin_conversations_path
    assert_select "[data-conversation]", 0
    get admin_conversation_path([ @arya.id, @brienne.id ].minmax.join("-"))
    assert_response :not_found
  end

  private

  # A legacy row as the importer writes it: validations skipped.
  def legacy_blank(from, to, text, match:)
    message = Message.new(sender: from, receiver: to, message: text, match: match, legacy_id: Message.maximum(:legacy_id).to_i + 1)
    message.save!(validate: false)
    message
  end
end
