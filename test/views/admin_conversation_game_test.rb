require "test_helper"

# [component] One game's group on the admin thread, rendered alone: its
# heading (match, status, winner, dates, count), the first-named player's
# bubbles left and the second's right, each named and dated, the text
# escaped, and a "show all" link only when earlier messages are hidden.
class AdminConversationGameTest < ActionView::TestCase
  include MatchPlay

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
    @match = Match.create!(home_user: @brienne, away_user: @arya, match_status: Match::FINISHED,
                           winner: @arya, finish_reason: "king", turn: 30)
    @key = "#{@arya.id}-#{@brienne.id}"
  end

  def say(from, to, text, at:, match: @match)
    Message.create!(sender: from, receiver: to, message: text, match: match, created_at: at, updated_at: at)
  end

  def draw(group, whole: false)
    render partial: "admin/conversations/game",
           locals: { group: group, users: [ @arya, @brienne ], conversation_key: @key, whole: whole }
  end

  test "a game's messages sit left for the first player and right for the second, oldest first" do
    say(@brienne, @arya, "<b>good luck</b>", at: Time.zone.local(2019, 3, 2, 18, 5))
    say(@arya, @brienne, "gg", at: Time.zone.local(2019, 3, 4, 9, 30))

    draw(ConversationThread.new(@arya, @brienne).page(1).groups.sole)
    assert_select "section[data-game=?]", @match.id.to_s
    assert_select "h2 a[href=?]", "/admin/matches/#{@match.id}", "Match ##{@match.id}"
    assert_select "[data-game-status]", /finished \(king\) · won by arya/
    assert_select "[data-game-span]", /2 messages · March 02, 2019\s+– March 04, 2019/
    bubbles = css_select("li.chat-message")
    assert_equal [ @brienne.id, @arya.id ].map(&:to_s), bubbles.map { _1["data-sender-id"] }
    assert_equal [ true, false ], bubbles.map { _1["class"].include?("is-right") }
    assert_select "li.is-right .font-semibold", "brienne"
    assert_select "li:not(.is-right) .font-semibold", "arya"
    assert_select "li time", /March 02, 2019 18:05/
    assert_select "li .chat-text b", 0, "message text is escaped"
    assert_includes rendered, "&lt;b&gt;good luck&lt;/b&gt;"
    assert_select "[data-earlier]", 0
  end

  test "messages outside any game get their own heading" do
    say(@arya, @brienne, "hello", at: 1.hour.ago, match: nil)

    draw(ConversationThread.new(@arya, @brienne).page(1).groups.sole)
    assert_select "section[data-game=none] h2", /Outside any game/
    assert_select "h2 a", 0
  end

  test "a capped group counts what it hides and links to the whole game" do
    4.times { |i| say(@arya, @brienne, "m#{i}", at: (10 - i).hours.ago) }

    draw(ConversationThread.new(@arya, @brienne, per_group: 3).page(1).groups.sole)
    assert_select "[data-earlier]", /1 earlier message not shown/
    assert_select "[data-earlier] a[href=?]", "/admin/conversations/#{@key}?game=#{@match.id}", "Show all 4"
    assert_select "li.chat-message", 3
  end

  test "the whole game's own page draws no show-all link" do
    4.times { |i| say(@arya, @brienne, "m#{i}", at: (10 - i).hours.ago) }

    draw(ConversationThread.new(@arya, @brienne, per_page: 3).game(@match.id, page: 2).groups.sole, whole: true)
    assert_select "[data-earlier]", 0
    assert_select "li.chat-message", 1
  end
end
