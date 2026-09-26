require "test_helper"

# [integration] The match chat, the inbox and the admin Conversations page
# through the controllers: who can read what, and who gets a 404.
class MessagesTest < ActionDispatch::IntegrationTest
  include MatchPlay

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
    @cersei = make_player("cersei")
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin")
    @match = Match.challenge!(@arya, "brienne")
  end

  # ---- The match chat --------------------------------------------------------

  test "a player sends a match message and their opponent reads it" do
    log_in_as(@arya)
    get match_path(@match)
    assert_select "turbo-frame#match_chat_messages[src=?]", match_messages_path(@match)

    post match_messages_path(@match), params: { message: "Good luck" }
    assert_redirected_to match_messages_path(@match)
    follow_redirect!
    assert_select "turbo-frame#match_chat_messages .chat-message.is-mine", /Good luck/

    message = Message.sole
    assert_equal [ @arya, @brienne, @match, false ], [ message.sender, message.receiver, message.match, message.read ]

    log_in_as(@brienne)
    get match_messages_path(@match)
    assert_select ".chat-message:not(.is-mine)", /arya.*Good luck/m
    assert message.reload.read, "reading the chat marks it read"
  end

  test "a blank message is refused inside the chat frame" do
    log_in_as(@arya)
    post match_messages_path(@match), params: { message: "  " }
    assert_response :unprocessable_entity
    assert_select "turbo-frame#match_chat_messages [role=alert]", /blank/
    assert_equal 0, Message.count
  end

  test "someone outside the match gets a 404 on its chat" do
    secret = "plan-#{SecureRandom.hex(4)}"
    Message.post_in_match!(@match, @arya, secret)
    log_in_as(@cersei)

    get match_messages_path(@match)
    assert_response :not_found
    assert_not_includes response.body, secret

    post match_messages_path(@match), params: { message: "let me in" }
    assert_response :not_found
    assert_equal 1, Message.count
  end

  test "a signed-out visitor cannot read a match chat" do
    get match_messages_path(@match)
    assert_response :redirect
    assert_no_match %r{/matches}, response.location
  end

  # ---- The inbox -------------------------------------------------------------

  test "the inbox lists a player's conversations newest first, with unread counts" do
    older = Match.challenge!(@cersei, "arya")
    Message.post_in_match!(older, @cersei, "from cersei").update_columns(created_at: 2.days.ago)
    Message.post_in_match!(@match, @brienne, "from brienne")
    Message.post_in_match!(Match.challenge!(@cersei, "brienne"), @cersei, "not arya's business")

    log_in_as(@arya)
    get inbox_path
    assert_response :success
    rows = css_select("[data-inbox] li").map { _1["data-conversation"] }
    assert_equal [ @brienne.id, @cersei.id ].map(&:to_s), rows
    assert_select "[data-conversation=?] .unread-dot", @brienne.id.to_s, "1"
    assert_no_match(/not arya's business/, response.body)

    get matches_path
    assert_select "[data-inbox-link]"
    assert_select ".unread-dot", "2"
  end

  test "a conversation shows the whole thread, marks it read, and takes a reply" do
    Message.post_in_match!(@match, @brienne, "rematch?")

    log_in_as(@arya)
    get conversation_path(@brienne.id)
    assert_response :success
    assert_select "[data-thread] .chat-message", /rematch\?/
    assert_select "[data-thread] a[href=?]", match_path(@match)
    assert_equal 0, Message.unread_by(@arya).count

    post reply_conversation_path(@brienne.id), params: { message: "Yes!" }
    assert_redirected_to conversation_path(@brienne.id, anchor: "latest")
    reply = Message.order(:id).last
    assert_equal [ @arya, @brienne, nil, "Yes!" ], [ reply.sender, reply.receiver, reply.match, reply.message ]

    post reply_conversation_path(@brienne.id), params: { message: "" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /blank/
  end

  test "a conversation is a 404 to anyone outside it, and where there is none" do
    Message.post_in_match!(@match, @arya, "between us")
    log_in_as(@cersei)

    get conversation_path(@arya.id)
    assert_response :not_found
    post reply_conversation_path(@arya.id), params: { message: "cold open" }
    assert_response :not_found
    assert_equal 1, Message.count
  end

  # ---- The admin Conversations page ------------------------------------------

  test "a non-admin gets 404 on admin conversations" do
    secret = "hello-#{SecureRandom.hex(4)}"
    Message.post_in_match!(@match, @arya, secret)
    log_in_as(@arya)

    key = "#{@arya.id}-#{@brienne.id}"
    [ admin_conversations_path, admin_conversation_path(key), admin_conversation_path(key, game: @match.id),
      admin_conversation_path(key, game: "none"), admin_match_path(@match) ].each do |path|
      get path
      assert_response :not_found, path
      assert_not_includes response.body, secret
    end
  end

  test "a signed-out visitor is sent to sign in from the admin page" do
    get admin_conversations_path
    assert_response :redirect
    assert_no_match %r{/admin}, response.location
  end

  test "an admin sees every conversation, newest first, and each one's matches" do
    Message.post_in_match!(@match, @arya, "older").update_columns(created_at: 1.day.ago)
    other = Match.challenge!(@cersei, "brienne")
    Message.post_in_match!(other, @cersei, "newer")

    log_in_as(@admin)
    get admin_conversations_path
    assert_response :success
    keys = css_select("[data-conversations] li").map { _1["data-conversation"] }
    assert_equal [ [ @brienne.id, @cersei.id ].minmax.join("-"), [ @arya.id, @brienne.id ].minmax.join("-") ], keys
    assert_select "a[data-match-link=?][href=?]", @match.id.to_s, admin_match_path(@match)
    assert_select "[data-total]", /2 conversations/
  end

  test "an admin searches by player and pages through results" do
    players = Array.new(Conversation::PER_PAGE + 1) { |n| make_player("pupil#{n}") }
    players.each_with_index do |player, n|
      Message.create!(sender: player, receiver: @arya, message: "hi #{n}", created_at: n.minutes.ago)
    end
    Message.create!(sender: @cersei, receiver: @brienne, message: "elsewhere")

    log_in_as(@admin)
    get admin_conversations_path(q: "ARYA")
    assert_select "[data-total]", /26 conversations with a player matching “ARYA”/
    assert_select "[data-conversations] li", Conversation::PER_PAGE
    assert_select "a[rel=next][href=?]", admin_conversations_path(q: "ARYA", page: 2)
    assert_no_match(/elsewhere/, response.body)

    get admin_conversations_path(q: "ARYA", page: 2)
    assert_select "[data-conversations] li", 1
    assert_select "[data-conversations]", /hi 25/

    get admin_conversations_path(q: "zzz")
    assert_select "[data-conversations-empty]"
  end

  test "an admin reads a whole conversation and a match's chat" do
    Message.post_in_match!(@match, @arya, "hello brienne")
    Message.create!(sender: @brienne, receiver: @arya, message: "outside any match")

    log_in_as(@admin)
    get admin_conversation_path("#{@brienne.id}-#{@arya.id}")
    assert_response :success
    assert_select "[data-thread] .chat-message", 2
    assert_select "[data-game=?] a[href=?]", @match.id.to_s, admin_match_path(@match)

    get admin_match_path(@match)
    assert_response :success
    assert_select "[data-thread] .chat-message", 1
    assert_select "[data-match-facts]", /pending/

    get admin_conversation_path("#{@arya.id}-#{@cersei.id}")
    assert_response :not_found
    get admin_conversation_path("nonsense")
    assert_response :not_found
  end

  test "an admin reads a thread grouped by game, arya left and brienne right, every word of it" do
    long = "#{"a very long line about elephants and trebuchets " * 18}<script>alert(1)</script>"
    Message.post_in_match!(@match, @arya, "before the game")
    Message.post_in_match!(@match, @brienne, long)
    Message.create!(sender: @arya, receiver: @brienne, message: "outside any game", created_at: 1.minute.from_now)
    key = "#{@arya.id}-#{@brienne.id}"

    log_in_as(@admin)
    get admin_conversations_path
    assert_select "a[data-thread-link=?][href=?]", key, admin_conversation_path(key)

    get admin_conversation_path(key)
    assert_response :success
    assert_select "[data-sides]", /arya.*left.*brienne.*right/m
    assert_select "[data-game]", 2
    assert_select "[data-game]:first-of-type h2", /Outside any game/
    assert_select "[data-game=?] [data-game-status]", @match.id.to_s, /pending/
    assert_select "[data-game=?] .chat-message", @match.id.to_s, 2
    assert_select "[data-game=?] .chat-message.is-right[data-sender-id=?]", @match.id.to_s, @brienne.id.to_s, 1
    assert_select "[data-game=?] .chat-message:not(.is-right)[data-sender-id=?]", @match.id.to_s, @arya.id.to_s, 1
    assert_includes response.body, long.split("<script>").first.strip, "no message is truncated"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes response.body, "<script>alert(1)"

    get admin_conversation_path(key, game: @match.id)
    assert_response :success
    assert_select "[data-game]", 1
    assert_select ".chat-message", 2
    get admin_conversation_path(key, game: "none")
    assert_select ".chat-message", 1
    get admin_conversation_path(key, game: 0)
    assert_response :not_found
  end

  test "the admin nav links the Conversations page for admins only" do
    log_in_as(@admin)
    get root_path
    assert_select "a[href='/admin/conversations']"

    log_in_as(@arya)
    get root_path
    assert_select "a[href='/admin/conversations']", 0
  end

  # ---- The privacy note ------------------------------------------------------

  test "the About page says admins can read messages" do
    get about_path
    assert_select "#privacy", /admins can read them/
  end
end
