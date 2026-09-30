require "application_system_test_case"

# [e2e] The live chat (task cyvasse-live-chat) in two real browsers, over the
# websocket: a message sent in a match's chat reaches the other player's Chat
# hub and thread as it is sent, with the navbar badge counting it and clearing
# once it is read; the reply comes back to the match chat the same way. Then
# the match chat's own behaviour: scrolling, a refused message, Enter on a
# touch screen, and the empty hub for someone who has played nobody.
#
# The test cable adapter subclasses the async one, so broadcasts reach the
# browsers in process (config/cable.yml).
class MatchChatSystemTest < ApplicationSystemTestCase
  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne")
    @match = Match.challenge!(@arya, "brienne")
    ChatSending::RATE_STORE.clear
  end

  NAV_CHAT = "header nav[aria-label=Main] a[href='/conversations']".freeze

  test "a match message reaches the other player live, and the badge counts it until it is read" do
    using_session("brienne") do
      sign_in(@brienne)
      visit conversations_path
      connected
      assert_selector "[data-say-hi='#{@arya.id}']", text: "arya"
      assert_selector NAV_CHAT, text: /\AChat\z/
    end

    sign_in(@arya)
    visit match_path(@match)
    connected
    within("[data-match-chat]") do
      assert_text "No messages yet. Say hello to brienne."
      fill_in "Message brienne", with: "Good luck, you will need it"
      click_on "Send"
      assert_selector ".chat-message.is-mine", text: "Good luck, you will need it"
      assert_field "Message brienne", with: "", wait: 2
    end

    using_session("brienne") do
      # Live, with no reload: the hub row arrives and the badge counts it.
      assert_selector "#conversation_#{@arya.id} .unread-dot", text: "1"
      assert_selector "#conversation_#{@arya.id} [data-preview]", text: "Good luck, you will need it"
      assert_no_selector "[data-say-hi='#{@arya.id}']"
      assert_selector NAV_CHAT, text: /\AChat\s*1\z/
      assert_selector "#{NAV_CHAT} span", text: "1"

      find("#conversation_#{@arya.id} a").click
      assert_selector "[data-thread] .chat-message:not(.is-mine)", text: "Good luck, you will need it"
      assert_no_selector "#{NAV_CHAT} span"
      connected
    end

    within("[data-match-chat]") do
      fill_in "Message brienne", with: "Your move"
      click_on "Send"
      assert_selector ".chat-message.is-mine", text: "Your move"
    end

    using_session("brienne") do
      # Into the open thread, live; seen, so it is marked read and the badge
      # that counted it clears again.
      assert_selector "[data-thread] .chat-message:not(.is-mine)", text: "Your move"
      assert_selector "[data-chat-target=announcer]", text: "New message from arya: Your move", visible: :all
      assert_no_selector "#{NAV_CHAT} span", wait: 5
      wait_until("brienne's copy is marked read") { Message.find_by(message: "Your move").read }

      fill_in "Message arya", with: "We shall see"
      click_on "Send"
      assert_selector "[data-thread] .chat-message.is-mine", text: "We shall see"
    end

    within("[data-match-chat]") do
      assert_selector ".chat-message:not(.is-mine)", text: "We shall see"
      assert_selector "[data-chat-target=announcer]", text: "New message from brienne: We shall see", visible: :all
    end

    assert_equal [ "Good luck, you will need it", "Your move", "We shall see" ], Message.chronological.pluck(:message)
    assert_equal [ @match.id, @match.id, nil ], Message.chronological.pluck(:match_id), "the hub reply is outside any match"
  end

  test "someone who has played nobody gets the empty hub and Play Now" do
    loner = User.create!(email: "loner@example.com", name: "Loner", username: "loner")
    sign_in(loner)
    visit conversations_path
    assert_text "Play a human to start a conversation"
    assert_button "Play Now"
    assert_selector NAV_CHAT, text: /\AChat\z/
  end

  test "a reader scrolled up keeps their place as messages arrive; at the bottom they follow" do
    30.times { |i| Message.post_in_match!(@match, i.even? ? @brienne : @arya, "Line #{i}") }
    sign_in(@arya)
    visit match_path(@match)
    connected
    assert_selector "[data-chat-log] .chat-message", text: "Line 29"
    wait_until("the chat opens on the newest message") { log_metric("scrollTop").positive? }

    page.execute_script("const log = document.querySelector('[data-chat-target=log]'); log.scrollTop = 0; log.dispatchEvent(new Event('scroll'))")
    Message.post_in_match!(@match, @brienne, "Are you still there?")
    assert_selector "[data-chat-log] .chat-message", text: "Are you still there?"
    assert_equal 0, log_metric("scrollTop"), "the reader was left where they were"
    assert_selector "[data-chat-target=announcer]", text: "New message from brienne: Are you still there?", visible: :all

    page.execute_script("const log = document.querySelector('[data-chat-target=log]'); log.scrollTop = log.scrollHeight; log.dispatchEvent(new Event('scroll'))")
    Message.post_in_match!(@match, @brienne, "Hello?")
    assert_selector "[data-chat-log] .chat-message", text: "Hello?"
    wait_until("a reader at the bottom follows new messages") do
      log_metric("scrollHeight") - log_metric("clientHeight") - log_metric("scrollTop") <= 1
    end
  end

  test "after the socket drops, the chat catches up on what it missed" do
    sign_in(@arya)
    visit match_path(@match)
    connected
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("@hotwired/turbo-rails").then(async ({ cable }) => {
        window.chatConsumer = await cable.getConsumer()
        window.chatConsumer.disconnect()
        done(true)
      })
    JS
    assert_no_selector "[data-match-chat] turbo-cable-stream-source[connected]", visible: :all
    Message.post_in_match!(@match, @brienne, "Sent while you were away")
    assert_no_text "Sent while you were away"

    page.execute_script("window.chatConsumer.connect()")
    assert_selector "[data-chat-log] .chat-message", text: "Sent while you were away", count: 1
  end

  test "Load earlier pages back through the conversation and keeps the reader's place" do
    (ChatThread::SHOWN + 5).times { |i| Message.post_in_match!(@match, i.even? ? @brienne : @arya, "Line #{i}") }
    sign_in(@arya)
    visit match_path(@match)
    assert_selector "[data-chat-log] .chat-message", count: ChatThread::SHOWN
    assert_no_selector ".chat-text", exact_text: "Line 4"
    page.execute_script("document.querySelector('[data-chat-target=log]').scrollTop = 0")
    click_on "Load earlier messages"
    assert_selector "[data-match-chat] .chat-text", exact_text: "Line 0"
    assert_selector "[data-match-chat] .chat-message", count: ChatThread::SHOWN + 5
    assert_no_link "Load earlier messages"
    assert_operator log_metric("scrollTop"), :>, 0, "the older messages landed above, not under the reader"
  end

  test "a refused message's reason shows and the draft is kept" do
    sign_in(@arya)
    visit match_path(@match)
    assert_text "No messages yet."
    field = find_field("Message brienne")
    page.execute_script("arguments[0].removeAttribute('maxlength')", field)
    field.set("x" * (Message::MAX_LENGTH + 1))
    click_on "Send"
    assert_selector "[data-chat-target=error]", text: "Message is too long"
    assert_equal Message::MAX_LENGTH + 1, find_field("Message brienne").value.length, "the draft is kept to fix"
    assert_equal 0, Message.count
  end

  test "on a touch screen Enter starts a new line and Send sends" do
    sign_in(@arya)
    visit match_path(@match)
    assert_text "No messages yet."
    page.execute_script(<<~JS)
      const real = window.matchMedia.bind(window)
      window.matchMedia = (query) => query === "(pointer: coarse)" ? { matches: true, media: query } : real(query)
    JS
    field = find_field("Message brienne")
    field.send_keys("First line", :enter, "second line")
    assert_equal "First line\nsecond line", field.value
    assert_equal 0, Message.count
    click_on "Send"
    assert_selector ".chat-message.is-mine", text: "second line"
    assert_equal "First line\nsecond line", Message.last.message
  end

  private

  # Every cable stream on the page subscribed, so nothing broadcast next is
  # missed.
  def connected
    assert_selector "turbo-cable-stream-source[connected]", minimum: 1, visible: :all
    assert_no_selector "turbo-cable-stream-source:not([connected])", visible: :all
  end

  def wait_until(what, seconds = 5)
    page.document.synchronize(seconds) { raise Capybara::ExpectationNotMet, what unless yield }
  end

  def log_metric(name)
    page.evaluate_script("document.querySelector('[data-chat-target=log]').#{name}")
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.player_name}"
  end
end
