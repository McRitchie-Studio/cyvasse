require "test_helper"

# [integration] The live chat (task cyvasse-live-chat) through the
# controllers: the match chat and the Chat hub show one conversation per
# pair, sending broadcasts to both players' streams and the pair's stream,
# the server refuses anyone the sender has not played, sending is rate
# limited, and who can read what (a 404 for everyone else). The admin
# Conversations pages close the file.
class MessagesTest < ActionDispatch::IntegrationTest
  include MatchPlay

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
    @cersei = make_player("cersei")
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin")
    @match = Match.challenge!(@arya, "brienne")
    ChatSending::RATE_STORE.clear
  end

  def pair_stream = ChatStreams.pair(@arya, @brienne)
  def thread_id = ChatStreams.thread_id(@arya, @brienne)
  def turbo = { "Accept" => "text/vnd.turbo-stream.html, text/html" }

  # A conversation from before the rule, between people who never played.
  def legacy_message(from, to, text)
    Message.new(sender: from, receiver: to, message: text, legacy_id: Message.maximum(:legacy_id).to_i + 1).tap { _1.save!(validate: false) }
  end

  # ---- The match chat --------------------------------------------------------

  test "the match chat shows the pair's whole conversation, not only this match's" do
    earlier = Match.challenge!(@brienne, "arya")
    Message.post_in_match!(earlier, @brienne, "gg last time")
    Message.send_direct!(@arya, @brienne, "rematch soon?")
    Message.post_in_match!(@match, @brienne, "here we go")

    log_in_as(@arya)
    get match_path(@match)
    assert_response :success
    assert_select "[data-match-chat] ##{thread_id} .chat-message", 3
    assert_select "[data-match-chat] ##{thread_id}", /gg last time.*rematch soon\?.*here we go/m
    assert_select "[data-match-chat] turbo-cable-stream-source[channel=ChatStreamsChannel]"
    assert_select "[data-match-chat] form[action=?]", match_messages_path(@match)
  end

  test "sending in a match records the match and broadcasts to the pair and to both players" do
    log_in_as(@arya)
    pair = user_a = user_b = nil
    user_b = capture_turbo_stream_broadcasts(ChatStreams.user(@brienne)) do
      user_a = capture_turbo_stream_broadcasts(ChatStreams.user(@arya)) do
        pair = capture_turbo_stream_broadcasts(pair_stream) do
          post match_messages_path(@match), params: { message: "Good luck" }, headers: turbo
        end
      end
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=append][target=?] .chat-message.is-mine", thread_id, /Good luck/
    message = Message.sole
    assert_equal [ @arya, @brienne, @match, false ], [ message.sender, message.receiver, message.match, message.read ]

    assert_equal %w[remove append], pair.map { _1["action"] }
    assert_equal thread_id, pair.last["target"]
    assert_includes pair.last.to_html, "message-#{message.id}"
    assert_not_includes pair.last.to_html, "is-mine", "one rendering for both people; the page marks its reader's own"

    assert_equal "conversation_#{@brienne.id}", user_a.find { _1["action"] == "prepend" }.at("li")["id"]
    assert_nil user_a.find { _1["action"] == "update" }, "the sender's badge does not change"
    assert_equal "conversation_#{@arya.id}", user_b.find { _1["action"] == "prepend" }.at("li")["id"]
    badge = user_b.find { _1["action"] == "update" }
    assert_equal ChatBroadcasts::NAV_LINK, badge["targets"]
    assert_match(/Chat\s*<span[^>]*>1</, badge.at("template").inner_html)
  end

  test "a refused match message comes back as the thread's error, and nothing is sent" do
    log_in_as(@arya)
    assert_no_turbo_stream_broadcasts(pair_stream) do
      post match_messages_path(@match), params: { message: "  " }, headers: turbo
    end
    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target=?] [role=alert]", "#{thread_id}_error", /blank/
    assert_equal 0, Message.count
  end

  test "someone outside the match gets a 404 on its chat" do
    log_in_as(@cersei)
    post match_messages_path(@match), params: { message: "let me in" }, headers: turbo
    assert_response :not_found
    assert_equal 0, Message.count
  end

  test "a computer player's match chat shows only while its remote runner reads it" do
    tyrion = User.seed_computer_player!("tyrion")
    match = Match.create!(home_user: @arya, away_user: tyrion, match_status: Match::IN_PROGRESS)
    log_in_as(@arya)

    get match_path(match)
    assert_select "[data-match-chat]", 0, "no runner, nobody to read it"

    BotToken.issue!(tyrion)
    get match_path(match)
    assert_select "[data-match-chat] form[action=?]", match_messages_path(match)
    post match_messages_path(match), params: { message: "Good luck, little lion." }, headers: turbo
    assert_response :success
    assert_equal tyrion, Message.sole.receiver
  end

  # ---- Who may message whom ----------------------------------------------------

  test "the server refuses a message to someone never played, from the hub" do
    log_in_as(@arya)
    get conversation_path(@cersei.id)
    assert_response :not_found, "no messages and no match: no conversation to open"

    post reply_conversation_path(@cersei.id), params: { message: "cold open" }, headers: turbo
    assert_response :not_found
    assert_equal 0, Message.count
  end

  test "a legacy conversation with someone never played stays readable, without a composer" do
    legacy_message(@cersei, @arya, "remember me?")
    log_in_as(@arya)

    get conversation_path(@cersei.id)
    assert_response :success
    assert_select "[data-thread] .chat-message", /remember me\?/
    assert_select "[data-thread] form", 0
    assert_select "[data-chat-closed]", /message only players you have played/

    post reply_conversation_path(@cersei.id), params: { message: "sorry, who?" }, headers: turbo
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /message only players you have played/
    assert_equal 1, Message.count
  end

  # ---- The Chat hub ------------------------------------------------------------

  test "the hub lists conversations with people newest first, unread counts, and people to say hi to" do
    older = Match.challenge!(@cersei, "arya")
    Message.post_in_match!(older, @cersei, "from cersei").update_columns(created_at: 2.days.ago)
    Message.post_in_match!(@match, @brienne, "from brienne")
    davos = make_player("davos")
    Match.challenge!(davos, "arya")
    Message.post_in_match!(Match.challenge!(@cersei, "brienne"), @cersei, "not arya's business")
    tyrion = User.seed_computer_player!("tyrion")
    bot_match = Match.create!(home_user: @arya, away_user: tyrion, match_status: Match::IN_PROGRESS)
    Message.post_in_match!(bot_match, tyrion, "Luck is for dice.")

    log_in_as(@arya)
    get conversations_path
    assert_response :success
    assert_equal [ @brienne.id, @cersei.id ].map(&:to_s), css_select("#chat_conversations li").map { _1["data-conversation"] }
    assert_select "#conversation_#{@brienne.id} .unread-dot", /1/
    assert_select "#conversation_#{@brienne.id} [data-preview]", "from brienne"
    assert_select "#conversation_#{@brienne.id} [data-avatar]"
    assert_select "#conversation_#{@cersei.id} .unread-dot", /1/
    assert_equal [ davos.id.to_s ], css_select("[data-say-hi]").map { _1["data-say-hi"] }, "played, never messaged; never a computer"
    assert_no_match(/not arya's business|Luck is for dice/, response.body)
    assert_select "[data-chat-hub-empty]", 0
    assert_select "a[href='/conversations']", /Chat\s*2/, "the navbar badge counts the two people's messages, not the computer's"
  end

  test "the hub's queries do not grow with its rows" do
    count = lambda do
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get conversations_path }
      queries
    end
    Message.post_in_match!(@match, @brienne, "one")
    log_in_as(@arya)
    few = count.call

    %w[davos edd fennel gilly].each do |name|
      person = make_player(name)
      Message.post_in_match!(Match.challenge!(person, "arya"), person, "hi from #{name}")
      Match.challenge!(make_player("#{name}_x"), "arya")
    end
    many = count.call
    assert_select "#chat_conversations li", 5
    assert_select "[data-say-hi]", 4
    assert_equal few, many
  end

  test "a player who has played no human gets the empty hub with Play Now" do
    get conversations_path
    assert_response :redirect, "signed out: sent to sign in"

    tyrion = User.seed_computer_player!("tyrion")
    bot_match = Match.create!(home_user: @cersei, away_user: tyrion, match_status: Match::FINISHED)
    Message.post_in_match!(bot_match, tyrion, "Well played.")
    log_in_as(@cersei)
    get conversations_path
    assert_select "[data-chat-hub-empty]", /Play a human to start a conversation/
    assert_select "[data-chat-hub-empty] form[action=?] button", live_seeks_path, "Play Now"
    assert_select "#chat_conversations", 0
  end

  test "saying hi opens an empty thread with a composer, and the first message starts the conversation" do
    log_in_as(@brienne)
    get conversations_path
    assert_select "[data-say-hi=?] a[href=?]", @arya.id.to_s, conversation_path(@arya.id, anchor: "latest")

    get conversation_path(@arya.id)
    assert_response :success
    assert_select "##{thread_id}_empty", /Say hello to arya/
    assert_select "[data-thread] form[action=?]", reply_conversation_path(@arya.id)

    streams = capture_turbo_stream_broadcasts(ChatStreams.user(@brienne)) do
      post reply_conversation_path(@arya.id), params: { message: "Hi, good game!" }, headers: turbo
    end
    assert_response :success
    assert_equal [ "say_hi_#{@arya.id}", "chat_hub_empty", "conversation_#{@arya.id}" ],
                 streams.select { _1["action"] == "remove" }.map { _1["target"] }
    reply = Message.sole
    assert_equal [ @brienne, @arya, nil, "Hi, good game!" ], [ reply.sender, reply.receiver, reply.match, reply.message ]
  end

  test "opening a thread marks it read and clears the badge live" do
    Message.post_in_match!(@match, @brienne, "rematch?")
    log_in_as(@arya)

    streams = capture_turbo_stream_broadcasts(ChatStreams.user(@arya)) { get conversation_path(@brienne.id) }
    assert_response :success
    assert_select "[data-thread] .chat-message", /rematch\?/
    assert_select "[data-thread] a[href=?]", match_path(@match)
    assert_equal 0, Message.unread_by(@arya).count
    badge = streams.find { _1["action"] == "update" }
    assert_equal "Chat", badge.at("template").inner_html.strip, "no unread messages, no badge"
    assert_equal "conversation_#{@brienne.id}", streams.find { _1["action"] == "replace" }["target"]
  end

  test "the read endpoint marks the pair read for the match chat; nothing unread, nothing sent" do
    Message.post_in_match!(@match, @brienne, "your move")
    log_in_as(@arya)

    post read_conversation_path(@brienne.id)
    assert_response :no_content
    assert_equal 0, @arya.unread_messages_count

    # (assert_no_turbo_stream_broadcasts counts the earlier ones too.)
    assert_empty capture_turbo_stream_broadcasts(ChatStreams.user(@arya)) { post read_conversation_path(@brienne.id) }
  end

  test "load earlier pages back through the thread, and since catches up after a dropped socket" do
    lines = Array.new(ChatThread::SHOWN + 3) { |i| Message.send_direct!(i.even? ? @arya : @brienne, i.even? ? @brienne : @arya, "Line #{i}") }
    log_in_as(@arya)

    get conversation_path(@brienne.id)
    assert_select "##{thread_id} .chat-message", ChatThread::SHOWN
    first_shown = lines[3]
    assert_select "turbo-frame#chat_earlier_#{thread_id}_#{first_shown.id} a[href=?]",
                  messages_conversation_path(@brienne.id, before: first_shown.id)

    get messages_conversation_path(@brienne.id, before: first_shown.id), headers: { "Turbo-Frame" => "chat_earlier_#{thread_id}_#{first_shown.id}" }
    assert_response :success
    assert_select "turbo-frame#chat_earlier_#{thread_id}_#{first_shown.id} .chat-message", 3
    assert_select "turbo-frame turbo-frame", 0, "nothing older remains"

    get messages_conversation_path(@brienne.id, after: lines[-2].id), headers: turbo
    assert_response :success
    assert_select "turbo-stream[action=append][target=?] .chat-message", thread_id, 1
    assert_select "turbo-stream[action=append] #message-#{lines.last.id}"
  end

  test "sending is rate limited" do
    log_in_as(@arya)
    ChatSending::RATE.times { |i| post match_messages_path(@match), params: { message: "spam #{i}" }, headers: turbo }
    assert_response :success

    post match_messages_path(@match), params: { message: "one too many" }, headers: turbo
    assert_response :too_many_requests
    assert_select "turbo-stream[action=replace] [role=alert]", /too fast/
    assert_equal ChatSending::RATE, Message.count
  end

  test "message text is escaped and capped at MAX_LENGTH" do
    log_in_as(@arya)
    post match_messages_path(@match), params: { message: "<script>alert(1)</script>" }, headers: turbo
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes response.body, "<script>alert(1)</script>"

    post match_messages_path(@match), params: { message: "x" * (Message::MAX_LENGTH + 1) }, headers: turbo
    assert_response :unprocessable_entity
    assert_equal 1, Message.count
  end

  test "a conversation is a 404 to anyone outside it" do
    Message.post_in_match!(@match, @arya, "between us")
    log_in_as(@cersei)

    get conversation_path(@arya.id)
    assert_response :not_found
    get messages_conversation_path(@arya.id, after: 0), headers: turbo
    assert_response :not_found
    post read_conversation_path(@arya.id)
    assert_response :not_found
    get conversation_path(@cersei.id)
    assert_response :not_found, "nor with yourself"
  end

  test "the old inbox address redirects to the hub, query and all" do
    log_in_as(@arya)
    get "/inbox?page=2"
    assert_redirected_to "/conversations?page=2"
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
      legacy_message(player, @arya, "hi #{n}").update_columns(created_at: n.minutes.ago)
    end
    legacy_message(@cersei, @brienne, "elsewhere")

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
    assert_select "[data-total]", /\A\s*3 messages\.\s/, "no space before the full stop on a one-game page"
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
