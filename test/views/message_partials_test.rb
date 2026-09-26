require "test_helper"

# [component] The shared message partials, rendered alone: one message (whose
# side it sits on, its match label and link, escaped text) and the pager.
class MessagePartialsTest < ActionView::TestCase
  include MatchPlay

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
    @match = Match.challenge!(@arya, "brienne")
    @message = Message.post_in_match!(@match, @arya, "<b>hi</b>\n\nsecond line")
  end

  test "the viewer's own message is marked mine and signed You" do
    render partial: "messages/message", locals: { message: @message, viewer: @arya }
    assert_select "li.chat-message.is-mine[data-message-id=?]", @message.id.to_s
    assert_select "li .font-semibold", "You"
    assert_select "li .chat-text p", 2
    assert_select "li .chat-text b", 0, "message text is escaped"
    assert_includes rendered, "&lt;b&gt;hi&lt;/b&gt;"
  end

  test "someone else's message carries their name and, when asked, its match" do
    render partial: "messages/message",
           locals: { message: @message, viewer: @brienne, show_match: true, match_link: ->(m) { "/admin/matches/#{m.id}" } }
    assert_select "li.chat-message:not(.is-mine)"
    assert_select "li .font-semibold", "arya"
    assert_select "li a[href=?]", "/admin/matches/#{@match.id}", "match ##{@match.id}"
  end

  test "a match link that answers nil labels the match without a link" do
    render partial: "messages/message", locals: { message: @message, show_match: true, match_link: ->(_) { nil } }
    assert_select "li a", 0
    assert_includes rendered, "match ##{@match.id}"
  end

  test "the pager shows newer and older links only where there is a page" do
    page = Conversation::Page.new(conversations: [], page: 2, total: 60, per_page: 25)
    render partial: "messages/pager", locals: { page: page, path: ->(n) { "/inbox?page=#{n}" } }
    assert_select "a[rel=prev][href='/inbox?page=1']"
    assert_select "a[rel=next][href='/inbox?page=3']"
    assert_includes rendered, "Page 2 of 3"
  end

  test "a single page draws no pager" do
    page = Conversation::Page.new(conversations: [], page: 1, total: 3, per_page: 25)
    render partial: "messages/pager", locals: { page: page, path: ->(n) { "/inbox?page=#{n}" } }
    assert_select "nav", 0
  end
end
