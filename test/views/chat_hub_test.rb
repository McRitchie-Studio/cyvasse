require "test_helper"

# [component] The Chat hub (conversations/index and its rows) and the live
# thread partial, rendered alone (task cyvasse-live-chat): conversations with
# avatars, previews and unread counts; people to say hi to; the empty state
# with its Play Now; and a thread without a composer where the reader may not
# send.
class ChatHubViewTest < ActionView::TestCase
  include MatchPlay

  setup do
    @arya, @brienne, @cersei, @davos = %w[arya brienne cersei davos].map { make_player(_1) }
    view.define_singleton_method(:current_user) { nil }
  end

  def render_hub_for(user)
    view.define_singleton_method(:current_user) { user }
    @page = Conversation.hub(user)
    @say_hi = user.played_humans.reject { |person| Message.between(user, person).exists? }
    render template: "conversations/index"
  end

  test "conversations newest first, each with avatar, name, preview, time and unread count" do
    Message.post_in_match!(Match.challenge!(@cersei, "arya"), @cersei, "older").update_columns(created_at: 1.day.ago)
    match = Match.challenge!(@arya, "brienne")
    Message.post_in_match!(match, @brienne, "one")
    Message.post_in_match!(match, @brienne, "two")
    Message.post_in_match!(match, @arya, "my reply")
    Match.challenge!(@davos, "arya")

    render_hub_for(@arya)

    assert_equal [ "conversation_#{@brienne.id}", "conversation_#{@cersei.id}" ], css_select("#chat_conversations > li").map { _1["id"] }
    assert_select "#conversation_#{@brienne.id}" do
      assert_select "[data-avatar]"
      assert_select "p.font-semibold", "brienne"
      assert_select "[data-preview]", "You: my reply"
      assert_select ".unread-dot", /\A2 unread\z/
      assert_select "time[datetime]"
    end
    assert_select "#conversation_#{@cersei.id} .unread-dot", /1/
    assert_select "#chat_say_hi [data-say-hi=?]", @davos.id.to_s do
      assert_select "a[href=?]", "/conversations/#{@davos.id}#latest", /davos.*Say hi/m
    end
    assert_select "[data-chat-hub-empty]", 0
  end

  test "a read conversation shows no unread count" do
    match = Match.challenge!(@arya, "brienne")
    Message.post_in_match!(match, @brienne, "hello")
    Message.mark_read!(Message.all, @arya)

    render_hub_for(@arya)
    assert_select "#conversation_#{@brienne.id} .unread-dot", 0
  end

  test "people played but never messaged: an empty conversation list, hidden, and Say hi" do
    Match.challenge!(@arya, "brienne")
    render_hub_for(@arya)

    assert_select "#chat_conversations.empty\\:hidden", 1
    assert_equal "", css_select("#chat_conversations").first.inner_html, "empty, so :empty hides it until a row arrives"
    assert_select "#chat_hub_empty", /Say hi to someone you have played/
    assert_select "[data-say-hi=?]", @brienne.id.to_s
  end

  test "no human opponent ever: explains and offers Play Now" do
    render_hub_for(@arya)

    assert_select "[data-chat-hub-empty]" do
      assert_select "p", /Play a human to start a conversation/
      assert_select "form[action='/live'][method=post] button", "Play Now"
    end
    assert_select "#chat_conversations", 0
  end

  test "a thread the reader may not send in has no composer and says why" do
    Message.new(sender: @cersei, receiver: @arya, message: "old times", legacy_id: 5).save!(validate: false)
    arya = @arya
    view.define_singleton_method(:current_user) { arya }
    render partial: "chat/thread", locals: { thread: ChatThread.new(@arya, @cersei), form_url: "/conversations/#{@cersei.id}/messages" }

    assert_select "[data-controller=chat] turbo-cable-stream-source[channel=ChatStreamsChannel]"
    assert_select "ol##{ChatStreams.thread_id(@arya, @cersei)} .chat-message", /old times/
    assert_select "form", 0
    assert_select "[data-chat-closed]", /message only players you have played/
  end

  test "a thread the reader may send in has the composer, capped at MAX_LENGTH" do
    Match.challenge!(@arya, "brienne")
    render partial: "chat/thread", locals: { thread: ChatThread.new(@arya, @brienne), form_url: "/x" }

    assert_select "##{ChatStreams.thread_id(@arya, @brienne)}_empty", /Say hello to brienne/
    assert_select "form[action='/x'] textarea[maxlength=?][required]", Message::MAX_LENGTH.to_s
    assert_select "label.sr-only", "Message brienne"
    assert_select "[role=alert][hidden]"
    assert_select "p.sr-only[aria-live=polite]"
  end
end
