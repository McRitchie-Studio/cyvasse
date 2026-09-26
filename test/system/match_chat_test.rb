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

  test "a reader scrolled up keeps their place when the chat reloads" do
    30.times { |i| Message.post_in_match!(@match, i.even? ? @brienne : @arya, "Line #{i}") }
    sign_in(@arya)
    visit match_path(@match)
    assert_selector "[data-chat-log] .chat-message", text: "Line 29"
    wait_until("the chat opens on the newest message") { log_metric("scrollTop").positive? }

    page.execute_script("document.querySelector('[data-chat-log]').scrollTop = 0")
    Message.post_in_match!(@match, @brienne, "Are you still there?")
    reload_chat
    assert_selector "[data-chat-log] .chat-message", text: "Are you still there?"
    assert_equal 0, log_metric("scrollTop"), "the reload left the reader where they were"
    assert_selector "[data-chat-target=announcer]", text: "New message from brienne: Are you still there?", visible: :all

    page.execute_script("const log = document.querySelector('[data-chat-log]'); log.scrollTop = log.scrollHeight")
    Message.post_in_match!(@match, @brienne, "Hello?")
    reload_chat
    assert_selector "[data-chat-log] .chat-message", text: "Hello?"
    assert_equal log_metric("scrollHeight") - log_metric("clientHeight"), log_metric("scrollTop"), "a reader at the bottom follows new messages"
  end

  test "a refused message's error survives the next reload" do
    sign_in(@arya)
    visit match_path(@match)
    assert_text "No messages yet."
    field = find_field("Message brienne")
    page.execute_script("arguments[0].removeAttribute('maxlength')", field)
    field.set("x" * (Message::MAX_LENGTH + 1))
    click_on "Send"
    assert_selector "[data-chat-target=error]", text: "Message is too long"

    reload_chat
    assert_text "No messages yet."
    assert_selector "[data-chat-target=error]", text: "Message is too long"
    assert_equal Message::MAX_LENGTH + 1, find_field("Message brienne").value.length, "the draft is kept to fix"
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

  def wait_until(what)
    page.document.synchronize(3) { raise Capybara::ExpectationNotMet, what unless yield }
  end

  def log_metric(name)
    page.evaluate_script("document.querySelector('[data-chat-log]').#{name}")
  end

  # What the chat's timer does every few seconds, now; returns once the frame
  # has loaded and the chat controller has handled the load.
  def reload_chat
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const chat = document.querySelector("[data-controller=chat]")
      chat.addEventListener("turbo:frame-load", () => done(true), { once: true })
      window.Stimulus.getControllerForElementAndIdentifier(chat, "chat").refresh()
    JS
  end

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end
end
