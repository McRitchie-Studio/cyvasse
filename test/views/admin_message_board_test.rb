require "test_helper"

# [component] The admin Message Board page (piece 15) rendered alone: each
# post with its author, their email and the date and time it was posted,
# the text escaped with its line breaks kept, the count of blank posts
# hidden, and an empty state.
class AdminMessageBoardTest < ActionView::TestCase
  include MatchPlay

  setup do
    @arya = make_player("arya")
    @nameless = User.create!(email: "nameless@example.com", name: "No Name")
  end

  def draw(blank: 0)
    @page = BoardPost.page(1)
    @blank = blank
    render template: "admin/message_board/index"
  end

  test "a post shows its author, their email, when it was posted, and its text escaped" do
    post = BoardPost.create!(user: @arya, message: "<b>anyone</b> up\nfor a game?", created_at: Time.utc(2015, 3, 1, 9, 30))
    draw
    assert_select "li[data-board-post=?]", post.id.to_s do
      assert_select "[data-author]", "arya"
      assert_select "span", "arya@example.com"
      assert_select "time[datetime=?]", post.created_at.iso8601, l(post.created_at, format: :long)
      assert_select ".chat-text p", /<b>anyone<\/b> up/
      assert_select ".chat-text br", 1
      assert_select ".chat-text b", 0
    end
  end

  test "an author with no username is named by their display name" do
    BoardPost.create!(user: @nameless, message: "hi")
    draw
    assert_select "[data-author]", @nameless.player_name
  end

  test "the header counts the posts shown and the blank ones hidden" do
    2.times { |i| BoardPost.create!(user: @arya, message: "post #{i}") }
    draw(blank: 3)
    assert_select "h1", "Message Board"
    assert_select "[data-total]", /2 posts, newest first/
    assert_select "[data-blank]", "3 blank posts kept but not shown."
  end

  test "with no posts it says so and shows no blank count" do
    draw
    assert_select "[data-board-empty]", "No board posts."
    assert_select "[data-blank]", 0
  end
end
